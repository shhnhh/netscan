import Foundation

enum NetworkInfo {
    struct LocalAddress {
        let ip: String
        let subnetMask: String
    }

    /// Reads the device's Wi-Fi (en0) IPv4 address and subnet mask via getifaddrs.
    /// Returns nil if not connected to Wi-Fi.
    static func currentWiFiAddress() -> LocalAddress? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var result: LocalAddress?
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" else { continue } // Wi-Fi on iOS

            var ip = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &ip, socklen_t(ip.count), nil, 0, NI_NUMERICHOST)

            guard let netmask = interface.ifa_netmask else { continue }
            var mask = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(netmask, socklen_t(netmask.pointee.sa_len),
                        &mask, socklen_t(mask.count), nil, 0, NI_NUMERICHOST)

            result = LocalAddress(ip: String(cString: ip), subnetMask: String(cString: mask))
            break
        }
        return result
    }

    /// Expands the *actual* subnet (by real prefix length, not an assumed
    /// /24) into host IPv4 addresses to probe, capped at `maxHosts`. The
    /// previous version only ever varied the last octet within the current
    /// /24 chunk — correct for home networks, but on anything wider (a /22
    /// office/campus network, for instance) it silently missed every host
    /// outside the very first 254 addresses. This does real CIDR math
    /// instead of assuming the mask shape.
    static func hostAddresses(in local: LocalAddress, maxHosts: Int = 512) -> [String] {
        guard let ipInt = ipv4ToUInt32(local.ip), let maskInt = ipv4ToUInt32(local.subnetMask) else { return [] }

        let networkInt = ipInt & maskInt
        let broadcastInt = networkInt | ~maskInt
        guard broadcastInt > networkInt + 1 else { return [] }

        let firstHost = networkInt + 1
        let usableCount = Int(broadcastInt - firstHost) // excludes the broadcast address itself
        let count = min(usableCount, maxHosts)
        guard count > 0 else { return [] }

        return (0..<count).map { uint32ToIPv4(firstHost + UInt32($0)) }
    }

    /// Best-effort default-gateway guesses. There's no public iOS API for the
    /// real default route, so this tries the two addresses routers actually
    /// sit on in practice: the first usable address (overwhelming majority
    /// of home/office networks) and the last usable address (some ISP
    /// routers/ONTs, notably in Russia/CIS, ship configured at the top of
    /// the range instead). Probing both beats guessing wrong and silently
    /// deep-scanning some unrelated host while the real router shows no
    /// open ports.
    static func gatewayGuesses(for local: LocalAddress) -> [String] {
        guard let ipInt = ipv4ToUInt32(local.ip), let maskInt = ipv4ToUInt32(local.subnetMask) else { return [] }
        let networkInt = ipInt & maskInt
        let broadcastInt = networkInt | ~maskInt
        guard broadcastInt > networkInt + 1 else { return [] }

        let first = uint32ToIPv4(networkInt + 1)
        let last = uint32ToIPv4(broadcastInt - 1)
        return first == last ? [first] : [first, last]
    }

    private static func ipv4ToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    private static func uint32ToIPv4(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }
}
