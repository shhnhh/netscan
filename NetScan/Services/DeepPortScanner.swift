import Foundation
import Network

/// On-demand, single-host port scan used when the user opens a device and
/// asks for a deeper look. Unlike SubnetScanner (which treats a refused
/// connection as proof-of-life for the whole ping-sweep), this only counts a
/// port as "open" when the TCP handshake actually completes — that
/// distinction matters because SecurityAnalyzer reasons about specific ports
/// being genuinely open.
actor DeepPortScanner {
    static let scanPorts: [Int] = [
        21, 22, 23, 25, 53, 80, 110, 135, 139, 143, 443, 445, 554, 631,
        1433, 2323, 3306, 3389, 5000, 5060, 5432, 5555, 5601, 5900, 5901,
        5984, 6000, 6379, 7000, 8000, 8080, 8081, 8291, 8443, 8554, 8888,
        9100, 9200, 11211, 27017, 34567, 37777, 37778, 62078,
    ]

    private static let bannerPorts: Set<Int> = [
        21, 22, 23, 25, 80, 110, 143, 443, 554, 3306, 5432, 5984, 6379,
        8000, 8080, 8081, 8443, 8554, 8888, 9200, 27017, 34567, 37777,
    ]

    private let connectTimeout: TimeInterval = 0.8
    private let maxConcurrent = 16

    struct ScanResult {
        let openPorts: [Int]
        let banners: [Int: String]
    }

    func scan(host: String) async -> ScanResult {
        var openPorts: [Int] = []

        await withTaskGroup(of: (Int, Bool).self) { group in
            var iterator = DeepPortScanner.scanPorts.makeIterator()

            func launchNext() {
                guard let port = iterator.next() else { return }
                group.addTask {
                    let open = await self.connectAttempt(host: host, port: port)
                    return (port, open)
                }
            }

            for _ in 0..<maxConcurrent { launchNext() }
            while let (port, open) = await group.next() {
                if open { openPorts.append(port) }
                launchNext()
            }
        }
        openPorts.sort()

        var banners: [Int: String] = [:]
        await withTaskGroup(of: (Int, String?).self) { group in
            for port in openPorts where DeepPortScanner.bannerPorts.contains(port) {
                group.addTask {
                    (port, await BannerGrabber.grab(host: host, port: port))
                }
            }
            for await (port, banner) in group {
                if let banner { banners[port] = banner }
            }
        }

        return ScanResult(openPorts: openPorts, banners: banners)
    }

    private func connectAttempt(host: String, port: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: UInt16(port))!,
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
                case .failed, .cancelled:
                    // Refused/unreachable means the port is not open — unlike
                    // SubnetScanner's liveness sweep, we don't treat a refusal
                    // as a positive signal here.
                    resumeOnce(false)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + connectTimeout) {
                resumeOnce(false)
            }
        }
    }
}
