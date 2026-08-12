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

    /// Set if any TCP probe fails with ENETDOWN — the documented signature
    /// of the Local Network permission being denied/stuck (Apple dev forum
    /// reports this state can persist even after re-enabling the permission
    /// in Settings, until the device is restarted). When this is set, an
    /// empty result means "probably can't see the network at all", not
    /// "genuinely no devices" — worth telling the user, not just going quiet.
    private(set) var localNetworkAccessLikelyBlocked = false

    @discardableResult
    func scan(
        hosts: [String],
        onDeviceFound: @escaping @Sendable (Device) -> Void,
        onProgress: @escaping @Sendable (_ completed: Int, _ total: Int) -> Void
    ) async -> Bool {
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

        return localNetworkAccessLikelyBlocked
    }

    private func probe(host: String) async -> Device? {
        let start = Date()

        async let pingAlive = ICMPPinger.ping(host: host, timeout: connectTimeout)

        // All 5 ports fire at once instead of one after another — with a
        // wider host list (see NetworkInfo's CIDR fix), scanning them
        // sequentially per host would multiply the worst case (every port
        // timing out) into several seconds per dead host.
        let openPorts: [Int] = await withTaskGroup(of: (UInt16, ProbeOutcome).self) { group in
            for port in probePorts {
                group.addTask {
                    (port, await self.connectAttempt(host: host, port: port))
                }
            }
            var result: [Int] = []
            for await (port, outcome) in group {
                switch outcome {
                case .open:
                    result.append(Int(port))
                case .networkDown:
                    localNetworkAccessLikelyBlocked = true
                case .closed:
                    break
                }
            }
            return result.sorted()
        }

        let alive = await pingAlive
        guard !openPorts.isEmpty || alive else { return nil }

        let elapsedMs = Date().timeIntervalSince(start) * 1000
        return Device(id: host, ipAddress: host, isReachable: true,
                      responseTimeMs: elapsedMs, openPorts: openPorts)
    }

    private enum ProbeOutcome {
        case open
        case closed
        case networkDown
    }

    private func connectAttempt(host: String, port: UInt16) async -> ProbeOutcome {
        await withCheckedContinuation { continuation in
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: params
            )

            var resumed = false
            let resumeOnce: (ProbeOutcome) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce(.open)
                case .failed(let error):
                    switch error {
                    // Connection refused still proves a host is present and responding.
                    case .posix(.ECONNREFUSED):
                        resumeOnce(.open)
                    case .posix(.ENETDOWN):
                        resumeOnce(.networkDown)
                    default:
                        resumeOnce(.closed)
                    }
                case .cancelled:
                    resumeOnce(.closed)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.6) {
                resumeOnce(.closed)
            }
        }
    }
}
