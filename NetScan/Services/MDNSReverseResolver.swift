import Darwin
import Foundation

/// Resolves a device's own hostname with one direct question: a unicast
/// mDNS PTR query for its reverse-DNS name (`<ip>.in-addr.arpa`), sent
/// straight to the host's UDP 5353 — RFC 6762 §5.1 explicitly allows
/// querying a responder directly instead of the 224.0.0.251 multicast
/// group, and any active mDNSResponder/Avahi answers immediately with
/// whatever name it's configured with.
///
/// This is simpler and more direct than the other naming paths already in
/// the app: `ReverseDNSResolver` asks the *router* for a PTR record, which
/// most consumer routers just don't have; `BonjourScanner` has to browse a
/// fixed list of advertised service types and hope the device speaks one of
/// them. This instead just asks the device itself "what's your name" and
/// can succeed for anything still running mDNS, regardless of which
/// services (if any) it happens to advertise.
enum MDNSReverseResolver {
    static func resolveHostname(host: String, timeout: TimeInterval = 1.0) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: performQuery(host: host, timeout: timeout))
            }
        }
    }

    private static func performQuery(host: String, timeout: TimeInterval) -> String? {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_port = UInt16(5353).bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else { return nil }
        let targetAddr = addr.sin_addr.s_addr

        guard let packet = makePTRQuery(host: host) else { return nil }
        let sent = packet.withUnsafeBytes { rawBuffer -> Int in
            withUnsafePointer(to: &addr) { addrPtr -> Int in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(sock, rawBuffer.baseAddress, rawBuffer.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }

            var pollFd = pollfd(fd: sock, events: Int16(POLLIN), revents: 0)
            guard poll(&pollFd, 1, Int32(remaining * 1000)) > 0 else { return nil }

            var buffer = [UInt8](repeating: 0, count: 1500)
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &from) { fromPtr -> Int in
                fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { fromSockaddr in
                    recvfrom(sock, &buffer, buffer.count, 0, fromSockaddr, &fromLen)
                }
            }
            guard received > 0, from.sin_addr.s_addr == targetAddr else { continue }

            return parsePTRResponse(buffer: buffer, count: received)
        }
    }

    /// Builds a standard DNS query (mDNS uses the same wire format) asking
    /// for the PTR record of the reversed-octet in-addr.arpa name — e.g.
    /// "254.19.10.10.in-addr.arpa" for 10.10.19.254.
    static func makePTRQuery(host: String) -> [UInt8]? {
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return nil }

        var packet: [UInt8] = []
        packet.append(contentsOf: [0x00, 0x00]) // transaction ID
        packet.append(contentsOf: [0x00, 0x00]) // flags: standard query
        packet.append(contentsOf: [0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) // QD=1

        let labels = [String(octets[3]), String(octets[2]), String(octets[1]), String(octets[0]), "in-addr", "arpa"]
        for label in labels {
            let bytes = Array(label.utf8)
            packet.append(UInt8(bytes.count))
            packet.append(contentsOf: bytes)
        }
        packet.append(0x00) // name terminator

        packet.append(contentsOf: [0x00, 0x0C]) // QTYPE = PTR
        packet.append(contentsOf: [0x00, 0x01]) // QCLASS = IN
        return packet
    }

    static func parsePTRResponse(buffer: [UInt8], count: Int) -> String? {
        guard count >= 12 else { return nil }
        let qdcount = Int(buffer[4]) << 8 | Int(buffer[5])
        let ancount = Int(buffer[6]) << 8 | Int(buffer[7])
        guard ancount > 0 else { return nil }

        var offset = 12
        for _ in 0..<qdcount {
            guard let (_, nameEnd) = decodeName(buffer, offset, count) else { return nil }
            offset = nameEnd + 4 // TYPE + CLASS
            guard offset <= count else { return nil }
        }

        for _ in 0..<ancount {
            guard let (_, nameEnd) = decodeName(buffer, offset, count) else { return nil }
            offset = nameEnd
            guard offset + 10 <= count else { return nil }
            let type = Int(buffer[offset]) << 8 | Int(buffer[offset + 1])
            let rdlength = Int(buffer[offset + 8]) << 8 | Int(buffer[offset + 9])
            offset += 10
            guard offset + rdlength <= count else { return nil }

            if type == 0x0C, let (name, _) = decodeName(buffer, offset, count) {
                return cleanHostname(name)
            }
            offset += rdlength
        }
        return nil
    }

    /// Decodes a (possibly compressed) DNS name starting at `start`,
    /// returning the dotted name and the offset just past its own encoding
    /// in the message (not past any pointer target it jumped to — that
    /// matches what callers need to keep walking sibling records). Bounds
    /// the number of compression-pointer hops so a malformed/adversarial
    /// packet can't cause a loop.
    static func decodeName(_ buffer: [UInt8], _ start: Int, _ count: Int) -> (String, Int)? {
        var labels: [String] = []
        var offset = start
        var endOfOwnEncoding: Int?
        var hops = 0

        while true {
            guard offset < count else { return nil }
            let lengthByte = buffer[offset]

            if lengthByte & 0xC0 == 0xC0 {
                guard offset + 1 < count else { return nil }
                if endOfOwnEncoding == nil { endOfOwnEncoding = offset + 2 }
                hops += 1
                guard hops < 20 else { return nil }
                let pointer = (Int(lengthByte & 0x3F) << 8) | Int(buffer[offset + 1])
                guard pointer < count else { return nil }
                offset = pointer
                continue
            }

            if lengthByte == 0 {
                let end = endOfOwnEncoding ?? (offset + 1)
                return (labels.joined(separator: "."), end)
            }

            let labelLength = Int(lengthByte)
            guard offset + 1 + labelLength <= count else { return nil }
            let labelBytes = buffer[(offset + 1)..<(offset + 1 + labelLength)]
            guard let label = String(bytes: labelBytes, encoding: .utf8) else { return nil }
            labels.append(label)
            offset += 1 + labelLength
        }
    }

    private static func cleanHostname(_ name: String) -> String? {
        var result = name
        if result.hasSuffix(".local") {
            result.removeLast(6)
        } else if result.hasSuffix(".") {
            result.removeLast()
        }
        return result.isEmpty ? nil : result
    }
}
