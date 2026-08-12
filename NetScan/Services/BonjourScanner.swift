import Foundation
import Network

/// Browses common Bonjour/mDNS service types to enrich device discovery with
/// human-readable names (e.g. "Living Room AirPlay", "Office Printer").
/// Must be kept in sync with NSBonjourServices in project.yml — iOS only
/// allows browsing service types declared in Info.plist.
final class BonjourScanner {
    private let serviceTypes = [
        "_http._tcp", "_https._tcp", "_ssh._tcp", "_ftp._tcp", "_smb._tcp",
        "_airplay._tcp", "_raop._tcp", "_ipp._tcp", "_printer._tcp", "_device-info._tcp"
    ]

    private var browsers: [NWBrowser] = []

    func start(onServiceFound: @escaping @Sendable (_ name: String, _ type: String) -> Void) {
        for type in serviceTypes {
            let params = NWParameters()
            params.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: params)

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    if case let .service(name, type, _, _) = result.endpoint {
                        onServiceFound(name, type)
                    }
                }
            }
            browser.start(queue: .global(qos: .utility))
            browsers.append(browser)
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
    }
}
