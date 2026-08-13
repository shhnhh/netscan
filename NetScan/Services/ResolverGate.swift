import Foundation

/// A counting semaphore for async tasks, used to cap how many of the
/// per-device naming resolvers (reverse DNS, mDNS PTR, lockdown, NetBIOS)
/// run at once.
///
/// Each discovered device now fires up to four of these concurrently, on
/// top of `SubnetScanner`'s own internal fan-out (32 hosts in flight, each
/// opening 14 TCP probes + 1 ICMP ping = up to ~480 concurrent sockets
/// during the sweep itself). Left completely unbounded, dozens of found
/// devices firing their extra resolvers *during* that already-busy sweep
/// window pushes well past what a sandboxed iOS process' file-descriptor
/// table comfortably holds — `socket()`/connection setup starts silently
/// failing under that pressure, and it's exactly the slower-to-answer,
/// many-open-port devices (printers, projectors) that are most likely to
/// lose the race and drop out of the results. This gate keeps the extra
/// resolvers' peak concurrency bounded regardless of how many devices are
/// found at once.
actor ResolverGate {
    static let shared = ResolverGate(limit: 6)

    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = limit
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
