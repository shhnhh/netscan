import Darwin
import Foundation

/// Discovers devices' user-set "friendly name" via SSDP/UPnP — the multicast
/// discovery protocol smart TVs, routers, speakers and most IoT gear use to
/// announce themselves, independent of Bonjour's NSBonjourServices allow-list
/// (SSDP is one well-known multicast group/port, not a browsable mDNS service
/// type, so it needs no Info.plist declaration). The name a UPnP device
/// publishes here is typically the same "device name" it publishes
/// everywhere else — including as its Bluetooth name — since most vendors
/// only let the user set one name for the whole device. We can't read
/// Bluetooth itself (no link between a BLE identity and a Wi-Fi IP exists on
/// iOS), but this gets us the same string through a network-visible door.
enum SSDPScanner {
    static func discover(timeout: TimeInterval = 2.5) async -> [(ip: String, name: String)] {
        let locations = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: performDiscovery(timeout: timeout))
            }
        }

        return await withTaskGroup(of: (String, String)?.self) { group in
            for (ip, location) in locations {
                group.addTask {
                    guard let name = await fetchFriendlyName(location: location) else { return nil }
                    return (ip, name)
                }
            }
            var results: [(ip: String, name: String)] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }
    }

    /// Sends an M-SEARCH multicast request and collects LOCATION headers from
    /// responses, keyed by the responder's source IP — read via recvfrom off
    /// each datagram (same reasoning as ICMPPinger: UDP is connectionless, so
    /// the source address must come from the packet, not be assumed).
    private static func performDiscovery(timeout: TimeInterval) -> [String: String] {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return [:] }
        defer { close(sock) }

        var groupAddr = sockaddr_in()
        groupAddr.sin_family = sa_family_t(AF_INET)
        groupAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        groupAddr.sin_port = UInt16(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &groupAddr.sin_addr)

        let request = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n"
        let bytes = Array(request.utf8)

        func send() {
            _ = bytes.withUnsafeBytes { rawBuffer -> Int in
                withUnsafePointer(to: &groupAddr) { addrPtr -> Int in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        sendto(sock, rawBuffer.baseAddress, rawBuffer.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        // Multicast UDP is lossy and plenty of consumer/IoT gear (printers,
        // projectors) only answers the first M-SEARCH it happens to catch —
        // a single send can just get dropped. Re-sending a few times across
        // the listening window costs nothing and catches stragglers a
        // one-shot send would silently miss.
        send()
        guard timeout > 0 else { return [:] }

        var results: [String: String] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var resendsRemaining = 2
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }

            if resendsRemaining > 0, remaining < timeout * Double(resendsRemaining) / 3 {
                send()
                resendsRemaining -= 1
            }

            var pollFd = pollfd(fd: sock, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&pollFd, 1, Int32(min(remaining, 0.5) * 1000))
            guard pollResult >= 0 else { break } // real socket error, not just "nothing yet"
            guard pollResult > 0 else { continue } // plain timeout on this slice — keep waiting

            var buffer = [UInt8](repeating: 0, count: 2048)
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &from) { fromPtr -> Int in
                fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { fromSockaddr in
                    recvfrom(sock, &buffer, buffer.count, 0, fromSockaddr, &fromLen)
                }
            }
            guard received > 0 else { continue }
            guard let response = String(bytes: buffer[0..<received], encoding: .utf8) else { continue }
            guard let location = extractHeader("LOCATION", from: response) else { continue }

            var addrBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var mutableFrom = from
            inet_ntop(AF_INET, &mutableFrom.sin_addr, &addrBuf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: addrBuf)

            if results[ip] == nil {
                results[ip] = location
            }
        }
        return results
    }

    private static func extractHeader(_ key: String, from response: String) -> String? {
        for line in response.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(key) == .orderedSame {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Fetches the device description XML at `location` and pulls out
    /// <friendlyName> — the UPnP spec's field for the user-visible name.
    private static func fetchFriendlyName(location: String) async -> String? {
        guard let url = URL(string: location) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let xml = String(data: data, encoding: .utf8) else { return nil }
        guard let start = xml.range(of: "<friendlyName>"), let end = xml.range(of: "</friendlyName>") else { return nil }
        let name = xml[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
