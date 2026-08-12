import Foundation
import Network

/// Discovers live hosts on the local subnet. Two independent liveness
/// signals run per host: a handful of TCP probes (connect succeeds, or is
/// actively refused — both prove something is listening) and, in parallel,
/// an ICMP echo via ICMPPinger. Devices with every scanned TCP port
/// closed/filtered but that still answer ICMP (common for phones, tablets,
/// IoT gear with no open services) would otherwise be missed entirely.
actor SubnetScanner {
    private let probePorts: [UInt16] = [80, 443, 22, 445, 62078]
    private let connectTimeout: TimeInterval = 0.6
    private let maxConcurrentProbes = 32

    func scan(
        hosts: [String],
        onDeviceFound: @escaping @Sendable (Device) -> Void,
        onProgress: @escaping @Sendable (_ completed: Int, _ total: Int) -> Void
    ) async {
        let total = hosts.count
        var completed = 0

        await withTaskGroup(of: Void.self) { group in
            var iterator = hosts.makeIterator()

            func launchNext() {
                guard let host = iterator.next() else { return }
                group.addTask { [weak self] in
                    guard let self else { return }
                    if let device = await self.probe(host: host) {
                        onDeviceFound(device)
                    }
                }
            }

            for _ in 0..<maxConcurrentProbes { launchNext() }
            while await group.next() != nil {
                completed += 1
                onProgress(completed, total)
                launchNext()
            }
        }
    }

    private func probe(host: String) async -> Device? {
        let start = Date()
        var openPorts: [Int] = []

        async let pingAlive = ICMPPinger.ping(host: host, timeout: connectTimeout)

        for port in probePorts {
            let reachable = await connectAttempt(host: host, port: port)
            if reachable {
                openPorts.append(Int(port))
            }
        }

        let alive = await pingAlive
        guard !openPorts.isEmpty || alive else { return nil }

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
