import Foundation
import Network

/// Queries the "lockdown" service iOS exposes on TCP 62078 — the same port
/// iTunes/Xcode use for Wi-Fi sync/debugging, and the one PlatformGuesser
/// already treats as "this is an iOS device" from the open port alone. The
/// service will answer a basic, unauthenticated `GetValue` request for
/// `DeviceName` with the device's actual set name (e.g. "Fedor's iPhone") —
/// no pairing/trust relationship is established or needed for this one
/// read-only query, the same class of probe network tools like nmap's
/// ios-devices script use. If the device (or iOS version) does refuse it,
/// this just returns nil and naming falls back to the vendor/IP as before.
enum LockdownClient {
    static func deviceName(host: String, timeout: TimeInterval = 2.0) async -> String? {
        await withCheckedContinuation { continuation in
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: 62078)!,
                using: params
            )

            var finished = false
            let finish: (String?) -> Void = { result in
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    sendQuery(connection: connection, finish: finish)
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
        }
    }

    /// Lockdown frames every message as a 4-byte big-endian length prefix
    /// followed by that many bytes of an XML plist — no relation to HTTP or
    /// any other framing, this is the protocol's own wire format.
    private static func sendQuery(connection: NWConnection, finish: @escaping (String?) -> Void) {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Request</key>
            <string>GetValue</string>
            <key>Key</key>
            <string>DeviceName</string>
            <key>Label</key>
            <string>NetScan</string>
        </dict>
        </plist>
        """
        guard let plistData = plist.data(using: .utf8) else { finish(nil); return }

        let length = UInt32(plistData.count)
        let lengthBytes: [UInt8] = [
            UInt8((length >> 24) & 0xFF), UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)
        ]
        var frame = Data(lengthBytes)
        frame.append(plistData)

        connection.send(content: frame, completion: .contentProcessed { error in
            guard error == nil else { finish(nil); return }
            receiveResponse(connection: connection, finish: finish)
        })
    }

    private static func receiveResponse(connection: NWConnection, finish: @escaping (String?) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { lengthData, _, _, error in
            guard let lengthData, lengthData.count == 4, error == nil else { finish(nil); return }
            let bytes = [UInt8](lengthData)
            let length = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            guard length > 0, length < 1_000_000 else { finish(nil); return }

            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { body, _, _, error in
                guard let body, error == nil,
                      let plistObject = try? PropertyListSerialization.propertyList(from: body, format: nil),
                      let dict = plistObject as? [String: Any],
                      let name = dict["Value"] as? String, !name.isEmpty else {
                    finish(nil)
                    return
                }
                finish(name)
            }
        }
    }
}
