import Darwin
import Foundation

/// Sends a Wake-on-LAN "magic packet" — a UDP broadcast that most NICs with
/// WoL enabled in firmware recognize regardless of what's running (or not
/// running) on the OS above them, which is the whole point: it can wake a
/// fully powered-off PC/NAS. No response is expected or waited for; success
/// here only means the packet went out, not that the target woke up.
enum WakeOnLAN {
    enum WakeError: Error {
        case invalidMAC
        case socketFailed
        case sendFailed
    }

    /// The magic packet is 6 bytes of 0xFF followed by the target MAC
    /// address repeated 16 times — a fixed 102-byte payload the NIC's
    /// wake-on-LAN circuitry scans for, defined by the original Wake-on-LAN
    /// spec and unchanged since.
    static func makeMagicPacket(mac: String) -> [UInt8]? {
        let hexPairs = mac.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard hexPairs.count == 6 else { return nil }
        let macBytes = hexPairs.compactMap { UInt8($0, radix: 16) }
        guard macBytes.count == 6 else { return nil }

        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }

    /// Broadcasts the magic packet on the local subnet (255.255.255.255,
    /// port 9 — the conventional "discard" port WoL traditionally targets).
    /// A LAN broadcast reaches the target as a link-layer frame regardless
    /// of its IP configuration at the time (it may not even have one, being
    /// powered off), which is why this doesn't send to the device's own IP.
    @discardableResult
    static func wake(mac: String) throws -> Bool {
        guard let packet = makeMagicPacket(mac: mac) else { throw WakeError.invalidMAC }

        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { throw WakeError.socketFailed }
        defer { close(sock) }

        var broadcastEnable: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_port = UInt16(9).bigEndian
        addr.sin_addr.s_addr = INADDR_BROADCAST

        let sent = packet.withUnsafeBytes { rawBuffer -> Int in
            withUnsafePointer(to: &addr) { addrPtr -> Int in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(sock, rawBuffer.baseAddress, rawBuffer.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { throw WakeError.sendFailed }
        return true
    }
}
