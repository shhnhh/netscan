import Network
import Foundation

/// Prints a plain test page by sending raw bytes straight to a printer's
/// port 9100 (RAW/JetDirect) — no driver, no IPP negotiation. This is the
/// same "just open a TCP socket and write bytes" mechanism JetDirect
/// printing has always used; real IPP (port 631) is a considerably heavier
/// protocol (binary attribute encoding, capability negotiation) that isn't
/// worth implementing just for a one-button test page.
enum RawPrinter {
    /// Wraps the page in a PJL header selecting PCL, which the wide
    /// majority of office/home network printers speaking 9100 understand —
    /// and even printers that don't recognize PJL/PCL at all typically just
    /// print the plain text they don't understand, so this degrades
    /// reasonably rather than failing silently.
    static func makeTestPage(deviceName: String) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = formatter.string(from: Date())

        let pjlHeader = "\u{1B}%-12345X@PJL\r\n@PJL ENTER LANGUAGE=PCL\r\n"
        let body = """
        NetScan — тестовая страница

        Устройство: \(deviceName)
        Напечатано: \(timestamp)

        Если ты видишь этот текст — печать по сети на этот принтер работает.
        """
        let pjlFooter = "\u{0C}\u{1B}%-12345X"

        return Data((pjlHeader + body + pjlFooter).utf8)
    }

    @discardableResult
    static func printTestPage(host: String, deviceName: String, timeout: TimeInterval = 5) async -> Bool {
        await withCheckedContinuation { continuation in
            let params = NWParameters.tcp
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: 9100)!,
                using: params
            )

            var finished = false
            let finish: (Bool) -> Void = { result in
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let data = makeTestPage(deviceName: deviceName)
                    connection.send(content: data, completion: .contentProcessed { error in
                        finish(error == nil)
                    })
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
        }
    }
}
