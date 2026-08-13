import Darwin
import Foundation

/// Minimal unprivileged ICMP echo ("ping") — the same SOCK_DGRAM/IPPROTO_ICMP
/// trick Apple's own "SimplePing" sample uses, available to sandboxed apps
/// without any entitlement (the kernel builds the IP header for you). Used
/// as a second, independent liveness signal alongside TCP probing, since
/// plenty of devices answer ICMP even with every scanned TCP port closed or
/// filtered — this is the main gap between us and Fing on device count.
enum ICMPPinger {
    static func ping(host: String, timeout: TimeInterval = 0.6) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: performPing(host: host, timeout: timeout))
            }
        }
    }

    private static func performPing(host: String, timeout: TimeInterval) -> Bool {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        guard host.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            return false
        }
        let targetAddr = addr.sin_addr.s_addr

        let identifier = UInt16.random(in: 0...UInt16.max)
        let packet = makeEchoPacket(identifier: identifier, sequence: 1)

        let sent = packet.withUnsafeBytes { rawBuffer -> Int in
            withUnsafePointer(to: &addr) { addrPtr -> Int in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(sock, rawBuffer.baseAddress, rawBuffer.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { return false }

        // Read in a loop until the deadline. The socket is unconnected, so it
        // receives *any* ICMP the process gets — a reply meant for another of
        // the 32 concurrent pings, or a Destination Unreachable from a router
        // — and we must ignore those, keep waiting, and only accept an Echo
        // Reply that actually came *from the address we pinged*. Counting the
        // stray packets as "alive" is what made a scan report the entire
        // address range (exactly maxHosts) as found.
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }

            var pollFd = pollfd(fd: sock, events: Int16(POLLIN), revents: 0)
            guard poll(&pollFd, 1, Int32(remaining * 1000)) > 0 else { return false }

            var buffer = [UInt8](repeating: 0, count: 128)
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &from) { fromPtr -> Int in
                fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { fromSockaddr in
                    recvfrom(sock, &buffer, buffer.count, 0, fromSockaddr, &fromLen)
                }
            }
            guard received > 0 else { return false }

            if from.sin_addr.s_addr == targetAddr, isEchoReply(buffer: buffer, count: received) {
                return true
            }
            // Stray/other-host packet — keep waiting within the remaining time.
        }
    }

    /// Decides whether a received packet is a genuine Echo Reply (a live
    /// host answering our ping) versus something like a Destination
    /// Unreachable — a router can send the latter for dead addresses on a
    /// subnet wider than the physical segment, and counting those as "alive"
    /// is what made a scan report the entire address range as found.
    ///
    /// Two things a previous version got wrong, both of which silently
    /// rejected *every* real reply (so only hosts with an open TCP port
    /// survived, collapsing the device count):
    ///
    /// 1. It assumed the IPv4 header is always prepended to the datagram.
    ///    Whether the kernel includes it on a SOCK_DGRAM ICMP socket varies,
    ///    so we detect it: a leading byte with version nibble 4 is an IPv4
    ///    header to skip; otherwise the ICMP message starts at byte 0.
    /// 2. It checked the ICMP identifier against the one we sent. On a
    ///    SOCK_DGRAM ICMP socket the kernel overwrites the identifier with
    ///    its own per-socket value, so our sent id never matches the reply.
    ///    The kernel already only delivers replies for this socket's own
    ///    sends, so that check bought nothing but false negatives — dropped.
    static func isEchoReply(buffer: [UInt8], count: Int) -> Bool {
        guard count >= 1 else { return false }

        var icmpOffset = 0
        if (buffer[0] >> 4) == 4 {
            let ipHeaderLength = Int(buffer[0] & 0x0F) * 4
            guard ipHeaderLength >= 20 else { return false }
            icmpOffset = ipHeaderLength
        }

        guard count > icmpOffset else { return false }
        return buffer[icmpOffset] == 0 // ICMP type 0 = Echo Reply
    }

    static func makeEchoPacket(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var bytes: [UInt8] = [
            8, 0, 0, 0, // type (echo request), code, checksum placeholder
            UInt8(identifier >> 8), UInt8(identifier & 0xFF),
            UInt8(sequence >> 8), UInt8(sequence & 0xFF),
        ]
        bytes.append(contentsOf: Array("netscan".utf8))

        let checksum = icmpChecksum(bytes)
        bytes[2] = UInt8(checksum >> 8)
        bytes[3] = UInt8(checksum & 0xFF)
        return bytes
    }

    static func icmpChecksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var buffer = bytes
        if buffer.count % 2 != 0 { buffer.append(0) }

        var index = 0
        while index < buffer.count {
            sum += (UInt32(buffer[index]) << 8) + UInt32(buffer[index + 1])
            index += 2
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return UInt16(~sum & 0xFFFF)
    }
}
