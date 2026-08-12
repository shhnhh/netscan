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
        "_airplay._tcp", "_raop._tcp", "_ipp._tcp", "_printer._tcp", "_device-info._tcp"
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

        let connection = NWConnection(to: result.endpoint, using: .tcp)
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
                onResolved(name, "\(address)")
            }
            finish()
        }

        connection.start(queue: queue)

        // Most Bonjour-advertised services accept the connection almost
        // instantly since the whole point is that something's listening —
        // this timeout is just a safety net for the rare service that
        // doesn't respond, so we don't leak connections indefinitely.
        queue.asyncAfter(deadline: .now() + 3) {
            finish()
        }
    }
}
