import Foundation
import Network

/// Grabs a single read of whatever a service says right after connecting.
/// For plaintext protocols (FTP/SSH/Telnet/SMTP/...) that's the greeting
/// banner they send unprompted; for HTTP/RTSP we send one minimal request
/// first. This is passive reconnaissance only — one request, no login
/// attempts, no follow-up traffic.
enum BannerGrabber {
    private static let httpPorts: Set<Int> = [80, 8000, 8080, 8081, 8443, 8888]
    private static let rtspPorts: Set<Int> = [554, 8554]

    static func grab(host: String, port: Int, timeout: TimeInterval = 1.2) async -> String? {
        await withCheckedContinuation { continuation in
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: UInt16(port))!,
                using: params
            )

            var resumed = false
            let finish: (String?) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if httpPorts.contains(port) {
                        let request = "GET / HTTP/1.0\r\nHost: \(host)\r\nConnection: close\r\n\r\n"
                        connection.send(content: request.data(using: .utf8), completion: .contentProcessed { _ in })
                    } else if rtspPorts.contains(port) {
                        // DESCRIBE (not OPTIONS) because it's the request whose
                        // 401-or-not response actually tells us whether the
                        // stream is behind a password — this reads only the
                        // text SDP header, never actual video/audio.
                        let request = "DESCRIBE rtsp://\(host):\(port)/ RTSP/1.0\r\nCSeq: 1\r\nAccept: application/sdp\r\n\r\n"
                        connection.send(content: request.data(using: .utf8), completion: .contentProcessed { _ in })
                    }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { data, _, _, _ in
                        if let data, !data.isEmpty {
                            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
                            finish(text)
                        } else {
                            finish(nil)
                        }
                    }
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
}
