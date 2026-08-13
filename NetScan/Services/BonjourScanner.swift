import Foundation
import Network

/// Browses common Bonjour/mDNS service types to enrich device discovery with
/// human-readable names (e.g. "Living Room AirPlay", "Office Printer").
/// Must be kept in sync with NSBonjourServices in project.yml — iOS only
/// allows browsing service types declared in Info.plist.
///
/// NWBrowser results only carry a `.service(name:type:domain:)` endpoint —
/// Apple deliberately doesn't hand over the resolved IP just from browsing
/// (would make trivial network mapping too easy). Getting the actual address
/// requires opening a real connection to the service and reading back its
/// resolved remote endpoint once connected, which is what `resolve(result:)`
/// does below.
final class BonjourScanner {
    private let serviceTypes = [
        "_http._tcp", "_https._tcp", "_ssh._tcp", "_ftp._tcp", "_smb._tcp",
        "_airplay._tcp", "_raop._tcp", "_ipp._tcp", "_printer._tcp", "_device-info._tcp",
        // Apple's own cross-device discovery/pairing protocols — this is
        // what actually carries an iPhone/iPad/Watch/Mac's set name, since
        // those devices otherwise run no server on any of the ports above.
        "_companion-link._tcp", "_rdlink._tcp", "_homekit._tcp",
        // Chromecast/Android TV and similar — advertises the user-set
        // device name the same way AirPlay does for Apple gear.
        "_googlecast._tcp"
    ]

    // Every browser and connection below runs its callbacks on this single
    // serial queue instead of the shared concurrent global queue — up to 10
    // NWBrowsers plus one NWConnection per discovered service would
    // otherwise mutate `browsers`/`resolvingConnections` from genuinely
    // concurrent threads.
    private let queue = DispatchQueue(label: "netscan.bonjour")

    private var browsers: [NWBrowser] = []
    private var resolvingConnections: [NWConnection] = []

    func start(onServiceResolved: @escaping @Sendable (_ name: String, _ ip: String) -> Void) {
        // Dispatched onto `queue` too (not just the browsers/connections it
        // creates) so a stop() immediately followed by a start() — e.g. the
        // scan screen re-appearing right after leaving it — can't race the
        // pending cleanup from the previous stop() against this loop's
        // `browsers.append`.
        queue.async { [weak self] in
            guard let self else { return }
            for type in self.serviceTypes {
                let params = NWParameters()
                params.includePeerToPeer = false
                let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: params)

                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    for result in results {
                        self?.resolve(result, onResolved: onServiceResolved)
                    }
                }
                browser.start(queue: self.queue)
                self.browsers.append(browser)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.browsers.forEach { $0.cancel() }
            self.browsers.removeAll()
            self.resolvingConnections.forEach { $0.cancel() }
            self.resolvingConnections.removeAll()
        }
    }

    /// Runs on `queue` (called from a browser's results handler, which is
    /// itself already on `queue`), so touching the shared arrays here is safe.
    private func resolve(_ result: NWBrowser.Result, onResolved: @escaping @Sendable (String, String) -> Void) {
        guard case let .service(name, _, _, _) = result.endpoint else { return }
        let cleanName = Self.cleanServiceName(name)

        // UDP, not TCP: we only need the address the service resolves to, and
        // a UDP NWConnection reaches `.ready` as soon as mDNS resolution and
        // routing succeed — it doesn't need anything actually listening on
        // the port. A TCP connection needs a real listener to complete its
        // handshake, which many advertised services don't have (e.g.
        // _device-info._tcp/_companion-link._tcp on an iPhone exist purely
        // for discovery, with no server behind them) — that's why those
        // devices' names weren't getting matched to an IP before.
        let connection = NWConnection(to: result.endpoint, using: .udp)
        resolvingConnections.append(connection)

        var finished = false
        let finish: () -> Void = { [weak self] in
            guard !finished else { return }
            finished = true
            connection.cancel()
            self?.resolvingConnections.removeAll { $0 === connection }
        }

        connection.stateUpdateHandler = { state in
            guard case .ready = state, let remote = connection.currentPath?.remoteEndpoint,
                  case let .hostPort(host, _) = remote else {
                if case .failed = state { finish() }
                if case .cancelled = state { finish() }
                return
            }
            if case let .ipv4(address) = host {
                onResolved(cleanName, Self.plainAddress("\(address)"))
            }
            finish()
        }

        connection.start(queue: queue)

        // Resolution over UDP is normally near-instant; this timeout is just
        // a safety net so an unresolvable service doesn't leak a connection.
        queue.asyncAfter(deadline: .now() + 3) {
            finish()
        }
    }

    /// AirPlay/RAOP (and some Companion-Link) service instances are named
    /// "<12-hex-digit-device-id>@<friendly name>" — e.g.
    /// "682F678C480A@MacBook" — rather than just the friendly name. Strip
    /// that machine-ID prefix so the display name matches what the device
    /// actually calls itself everywhere else.
    static func cleanServiceName(_ name: String) -> String {
        guard let atIndex = name.firstIndex(of: "@") else { return name }
        let prefix = name[name.startIndex..<atIndex]
        guard prefix.count == 12, prefix.allSatisfy({ $0.isHexDigit }) else { return name }
        return String(name[name.index(after: atIndex)...])
    }

    /// Network.framework's IPv4Address/IPv6Address stringify with a
    /// "%interfaceName" suffix (e.g. "192.168.1.5%en0") when the address is
    /// bound to a specific interface, which it always is here since it comes
    /// off an active connection over Wi-Fi. That suffix isn't part of the
    /// address and breaks matching it against the plain-IP device list, so
    /// it's stripped before the address is used anywhere else.
    static func plainAddress(_ raw: String) -> String {
        raw.split(separator: "%", maxSplits: 1).first.map(String.init) ?? raw
    }
}
