import Foundation

struct Device: Identifiable, Hashable {
    let id: String // IP address, unique per scan
    var ipAddress: String
    var hostname: String?
    var bonjourName: String?
    var isReachable: Bool = false
    var responseTimeMs: Double?
    var openPorts: [Int] = []

    var displayName: String {
        bonjourName ?? hostname ?? ipAddress
    }
}

/// Common TCP ports probed both to detect liveness and to hint at what a device is.
enum WellKnownPort: Int, CaseIterable {
    case ftp = 21
    case ssh = 22
    case telnet = 23
    case dns = 53
    case http = 80
    case https = 443
    case smb = 445
    case airplay = 7000
    case ipp = 631
    case rtsp = 554
    case altHttp = 8080
    case lockdown = 62078 // iOS device services

    var label: String {
        switch self {
        case .ftp: return "FTP"
        case .ssh: return "SSH"
        case .telnet: return "Telnet"
        case .dns: return "DNS"
        case .http: return "HTTP"
        case .https: return "HTTPS"
        case .smb: return "SMB"
        case .airplay: return "AirPlay"
        case .ipp: return "IPP (Printer)"
        case .rtsp: return "RTSP"
        case .altHttp: return "HTTP (alt)"
        case .lockdown: return "iOS device"
        }
    }
}
