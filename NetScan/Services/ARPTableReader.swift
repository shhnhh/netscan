import Darwin
import Foundation

/// Reads the kernel's already-populated ARP cache via the same sysctl(3)
/// mechanism the `arp -a` command uses (CTL_NET/PF_ROUTE/NET_RT_FLAGS/
/// RTF_LLINFO) — a public, unprivileged BSD API. We only read entries the OS
/// already learned by talking to the LAN normally (which our own TCP/ICMP
/// probing during a scan naturally triggers); nothing is actively probed
/// here, no packets get sent by this reader itself.
///
/// Deliberately avoids relying on the `sockaddr_inarp` type (used to parse
/// the entry's IP) by reading its fields at fixed byte offsets instead —
/// every BSD sockaddr variant shares the same `len/family/port/addr` prefix
/// layout, so this doesn't depend on that specific struct being importable
/// into Swift, only on `rt_msghdr`, which is far more commonly used.
enum ARPTableReader {
    static func currentEntries() -> [String: String] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var neededSize = 0
        guard sysctl(&mib, 6, nil, &neededSize, nil, 0) == 0, neededSize > 0 else { return [:] }

        var buffer = [UInt8](repeating: 0, count: neededSize)
        guard sysctl(&mib, 6, &buffer, &neededSize, nil, 0) == 0 else { return [:] }

        var result: [String: String] = [:]
        var offset = 0
        let headerSize = MemoryLayout<rt_msghdr>.size

        buffer.withUnsafeBytes { raw in
            while offset + headerSize <= neededSize {
                let msgLen = Int(raw.load(fromByteOffset: offset, as: UInt16.self))
                guard msgLen > 0, offset + msgLen <= neededSize else { return }

                let sinOffset = offset + headerSize
                guard sinOffset + 8 <= offset + msgLen else {
                    offset += msgLen
                    return
                }
                let sinLen = Int(raw.load(fromByteOffset: sinOffset, as: UInt8.self))
                let ipBytes = (0..<4).map { raw.load(fromByteOffset: sinOffset + 4 + $0, as: UInt8.self) }
                let ip = ipBytes.map(String.init).joined(separator: ".")

                // sockaddr_dl: 1B len, 1B family, 2B index, 1B type, 1B nlen,
                // 1B alen, 1B slen, then sdl_data (interface name + address).
                let sdlOffset = sinOffset + max(sinLen, 8)
                guard sdlOffset + 8 <= offset + msgLen else {
                    offset += msgLen
                    return
                }
                let sdlNlen = Int(raw.load(fromByteOffset: sdlOffset + 5, as: UInt8.self))
                let sdlAlen = Int(raw.load(fromByteOffset: sdlOffset + 6, as: UInt8.self))

                if sdlAlen == 6 {
                    let macStart = sdlOffset + 8 + sdlNlen
                    if macStart + 6 <= offset + msgLen {
                        let macBytes = (0..<6).map { raw.load(fromByteOffset: macStart + $0, as: UInt8.self) }
                        result[ip] = macBytes.map { String(format: "%02x", $0) }.joined(separator: ":")
                    }
                }

                offset += msgLen
            }
        }

        return result
    }
}
