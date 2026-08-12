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

    /// Expands a /24 (or narrower) subnet into a list of host IPv4 addresses to probe.
    /// Deliberately caps the range to avoid scanning huge subnets on accident.
    static func hostAddresses(in local: LocalAddress, maxHosts: Int = 254) -> [String] {
        let ipParts = local.ip.split(separator: ".").compactMap { UInt8($0) }
        let maskParts = local.subnetMask.split(separator: ".").compactMap { UInt8($0) }
        guard ipParts.count == 4, maskParts.count == 4 else { return [] }

        let network = zip(ipParts, maskParts).map { $0 & $1 }
        let hostBits = maskParts.map { (~$0) }

        // Only handle the common case (/24 or smaller range) to keep scans fast.
        let lastOctetRange: [UInt8]
        if hostBits[0] == 0, hostBits[1] == 0, hostBits[2] == 0 {
            let hostMax = Int(hostBits[3])
            lastOctetRange = (1..<max(hostMax, 1)).map { UInt8($0) }
        } else {
            lastOctetRange = Array(1...254)
        }

        let capped = lastOctetRange.prefix(maxHosts)
        return capped.map { "\(network[0]).\(network[1]).\(network[2]).\($0)" }
    }
}
