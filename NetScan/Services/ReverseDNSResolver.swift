import Foundation

/// Resolves an IP to a hostname via reverse DNS (PTR lookup) — this is how
/// Fing shows a device's actual name instead of just its IP: most home
/// routers act as a local DNS server and answer PTR queries with the
/// hostname a device announced when it requested its DHCP lease. Not every
/// device/router supports this; nil just means no name was available, not
/// an error worth surfacing.
enum ReverseDNSResolver {
    static func resolve(ip: String, timeout: TimeInterval = 2.5) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            // getnameinfo() is a blocking call with no built-in timeout, and
            // can't be cancelled once started — this doesn't stop the
            // background thread early, but it does make sure the caller
            // never waits past `timeout` regardless. Both the real result
            // and the timeout funnel through the same serial queue so only
            // one of them ever resumes the continuation.
            let resumeQueue = DispatchQueue(label: "netscan.reverse-dns.resume")
            var resumed = false

            DispatchQueue.global(qos: .utility).async {
                let name = performLookup(ip: ip)
                resumeQueue.async {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: name)
                }
            }

            resumeQueue.asyncAfter(deadline: .now() + timeout) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: nil)
            }
        }
    }

    private static func performLookup(ip: String) -> String? {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        guard ip.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else { return nil }

        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &addr) { addrPtr -> Int32 in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                // NI_NAMEREQD: fail rather than fall back to returning the
                // IP as a string — we only want a genuine name here.
                getnameinfo(sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size),
                            &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard result == 0 else { return nil }
        let name = String(cString: host)
        return name.isEmpty ? nil : name
    }
}
