import Foundation
import Network

/// Discovers live hosts on the local subnet by attempting short-lived TCP
/// connections to a handful of commonly-open ports. A host is considered
/// reachable if any probe connects or is actively refused (both prove
/// something is listening on that IP).
actor SubnetScanner {
    private let probePorts: [UInt16] = [80, 443, 22, 445, 62078]
    private let connectTimeout: TimeInterval = 0.6
    private let maxConcurrentProbes = 32

    func scan(hosts: [String], onDeviceFound: @escaping @Sendable (Device) -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = hosts.makeIterator()
            var active = 0

            func launchNext() {
                guard let host = iterator.next() else { return }
                active += 1
                group.addTask { [weak self] in
                    guard let self else { return }
                    if let device = await self.probe(host: host) {
                        onDeviceFound(device)
                    }
                }
            }

            for _ in 0..<maxConcurrentProbes { launchNext() }
            while await group.next() != nil {
                active -= 1
                launchNext()
            }
        }
    }

    private func probe(host: String) async -> Device? {
        let start = Date()
        var openPorts: [Int] = []

        for port in probePorts {
            let reachable = await connectAttempt(host: host, port: port)
            if reachable {
                openPorts.append(Int(port))
            }
        }

        guard !openPorts.isEmpty else { return nil }
        let elapsedMs = Date().timeIntervalSince(start) * 1000
        return Device(id: host, ipAddress: host, isReachable: true,
                      responseTimeMs: elapsedMs, openPorts: openPorts)
    }

    private func connectAttempt(host: String, port: UInt16) async -> Bool {
        await withCheckedContinuation { continuation in
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: params
            )

            var resumed = false
            let resumeOnce: (Bool) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce(true)
                case .failed(let error):
                    // Connection refused still proves a host is present and responding.
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        resumeOnce(true)
                    } else {
                        resumeOnce(false)
                    }
                case .cancelled:
                    resumeOnce(false)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.6) {
                resumeOnce(false)
            }
        }
    }
}
