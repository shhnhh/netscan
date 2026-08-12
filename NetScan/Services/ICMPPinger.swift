import Darwin
import Foundation

/// Minimal unprivileged ICMP echo ("ping") — the same SOCK_DGRAM/IPPROTO_ICMP
/// trick Apple's own "SimplePing" sample uses, available to sandboxed apps
/// without any entitlement (the kernel builds the IP header for you). Used
/// as a second, independent liveness signal alongside TCP probing, since
/// plenty of devices answer ICMP even with every scanned TCP port closed or
/// filtered — this is the main gap between us and Fing on device count.
///
/// We deliberately don't parse the reply's IP/ICMP headers (BSD ICMP
/// datagram sockets prepend a variable-length IP header we'd have to
/// account for, and we can't verify that parsing on real hardware without a
/// Mac). Any bytes back on our own ephemeral socket within the timeout are
/// treated as "alive" — a reasonable simplification for a liveness hint.
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

        var pollFd = pollfd(fd: sock, events: Int16(POLLIN), revents: 0)
        guard poll(&pollFd, 1, Int32(timeout * 1000)) > 0 else { return false }

        var buffer = [UInt8](repeating: 0, count: 128)
        let received = recv(sock, &buffer, buffer.count, 0)
        return received > 0
    }

    private static func makeEchoPacket(identifier: UInt16, sequence: UInt16) -> [UInt8] {
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

    private static func icmpChecksum(_ bytes: [UInt8]) -> UInt16 {
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
