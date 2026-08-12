import Network
import Foundation

/// Sends a standard Wake-on-LAN "magic packet" — 6 bytes of 0xFF followed by
/// the target MAC repeated 16 times — as a UDP broadcast. Needs the target's
/// MAC (from ARPTableReader) and for WoL to be enabled on that device; we
/// have no way to verify either from here, so this is fire-and-forget.
enum WakeOnLAN {
    static func send(toMac mac: String) {
        guard let macBytes = parseMac(mac) else { return }

        var payload = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            payload.append(contentsOf: macBytes)
        }

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let connection = NWConnection(
            host: NWEndpoint.Host("255.255.255.255"),
            port: NWEndpoint.Port(rawValue: 9)!,
            using: params
        )

        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: payload, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else if case .failed = state {
                connection.cancel()
            }
        }
        connection.start(queue: .global(qos: .utility))
    }

    private static func parseMac(_ mac: String) -> [UInt8]? {
        let parts = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard parts.count == 6 else { return nil }
        return parts
    }
}
