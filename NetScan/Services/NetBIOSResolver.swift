import Darwin
import Foundation

/// Resolves a Windows/SMB host's name via NBSTAT (NetBIOS Name Service node
/// status query, RFC 1002) — the same unauthenticated UDP 137 query
/// "Advanced IP Scanner", Fing and friends use for Windows machines, which
/// mostly don't run any of the Bonjour/SSDP/lockdown services this app
/// already tries but still answer this decades-old query out of the box.
enum NetBIOSResolver {
    static func resolveName(host: String, timeout: TimeInterval = 1.0) async -> String? {
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
        addr.sin_port = UInt16(137).bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else { return nil }
        let targetAddr = addr.sin_addr.s_addr

        let packet = makeNBSTATQuery()
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

            var buffer = [UInt8](repeating: 0, count: 1024)
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &from) { fromPtr -> Int in
                fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { fromSockaddr in
                    recvfrom(sock, &buffer, buffer.count, 0, fromSockaddr, &fromLen)
                }
            }
            guard received > 0, from.sin_addr.s_addr == targetAddr else { continue }

            if let name = parseNBSTATResponse(buffer: buffer, count: received) {
                return name
            }
            // A reply came from the right host but didn't parse into a
            // usable name (e.g. only group/workgroup names) — nothing more
            // will arrive for a single unicast query, so stop here.
            return nil
        }
    }

    /// Builds an NBSTAT ("node status") query for the wildcard name "*" —
    /// the standard way to ask "who are you" without knowing a target name
    /// up front. NetBIOS names are transmitted "first-level encoded": each
    /// raw byte's two nibbles become two ASCII letters (0x41 + nibble),
    /// turning the 16-byte name into a 32-byte encoded label.
    private static func makeNBSTATQuery() -> [UInt8] {
        var packet: [UInt8] = []
        packet.append(contentsOf: [0x82, 0x28]) // transaction ID
        packet.append(contentsOf: [0x00, 0x00]) // flags: standard query
        packet.append(contentsOf: [0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) // QD=1, AN/NS/AR=0

        packet.append(0x20) // encoded name length
        let wildcard: [UInt8] = [UInt8(ascii: "*")] + [UInt8](repeating: 0, count: 15)
        for byte in wildcard {
            packet.append(0x41 + (byte >> 4))
            packet.append(0x41 + (byte & 0x0F))
        }
        packet.append(0x00) // name terminator

        packet.append(contentsOf: [0x00, 0x21]) // QTYPE = NBSTAT
        packet.append(contentsOf: [0x00, 0x01]) // QCLASS = IN
        return packet
    }

    /// Walks the response as a generic DNS-shaped message (question section
    /// may or may not be echoed back, depending on implementation) to reach
    /// the NBSTAT answer's RDATA, rather than assuming a fixed offset.
    private static func parseNBSTATResponse(buffer: [UInt8], count: Int) -> String? {
        guard count >= 12 else { return nil }
        let qdcount = Int(buffer[4]) << 8 | Int(buffer[5])
        let ancount = Int(buffer[6]) << 8 | Int(buffer[7])
        guard ancount > 0 else { return nil }

        var offset = 12
        for _ in 0..<qdcount {
            guard let nameEnd = skipName(buffer, offset, count) else { return nil }
            offset = nameEnd + 4 // TYPE + CLASS
            guard offset <= count else { return nil }
        }

        for _ in 0..<ancount {
            guard let nameEnd = skipName(buffer, offset, count) else { return nil }
            offset = nameEnd
            guard offset + 10 <= count else { return nil }
            let type = Int(buffer[offset]) << 8 | Int(buffer[offset + 1])
            let rdlength = Int(buffer[offset + 8]) << 8 | Int(buffer[offset + 9])
            offset += 10
            guard offset + rdlength <= count else { return nil }

            if type == 0x21 {
                return parseNodeNameTable(buffer: buffer, start: offset, rdlength: rdlength)
            }
            offset += rdlength
        }
        return nil
    }

    private static func skipName(_ buffer: [UInt8], _ start: Int, _ count: Int) -> Int? {
        guard start < count else { return nil }
        if buffer[start] & 0xC0 == 0xC0 {
            return start + 2
        }
        var offset = start
        while offset < count, buffer[offset] != 0 {
            offset += Int(buffer[offset]) + 1
        }
        guard offset + 1 <= count else { return nil }
        return offset + 1
    }

    /// RDATA is: 1 byte name count, then that many 18-byte entries (15-byte
    /// space-padded name + 1 byte suffix + 2 bytes flags). Suffix 0x00 is
    /// the machine's own "workstation" name; the flags' group bit (0x8000)
    /// marks workgroup/domain names, which aren't what we want here.
    private static func parseNodeNameTable(buffer: [UInt8], start: Int, rdlength: Int) -> String? {
        guard rdlength > 0, start < buffer.count else { return nil }
        let numNames = Int(buffer[start])
        var offset = start + 1
        let sectionEnd = min(start + rdlength, buffer.count)

        for _ in 0..<numNames {
            guard offset + 18 <= sectionEnd else { break }
            let nameBytes = buffer[offset..<(offset + 15)]
            let suffix = buffer[offset + 15]
            let flags = UInt16(buffer[offset + 16]) << 8 | UInt16(buffer[offset + 17])
            offset += 18

            guard suffix == 0x00, flags & 0x8000 == 0 else { continue }
            if let name = String(bytes: nameBytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces),
               !name.isEmpty {
                return name
            }
        }
        return nil
    }
}
