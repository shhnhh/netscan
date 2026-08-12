import Foundation

struct Device: Identifiable, Hashable {
    let id: String // IP address, unique per scan
    var ipAddress: String
    var hostname: String?
    var bonjourName: String?
    var isReachable: Bool = false
    var responseTimeMs: Double?
    var openPorts: [Int] = []
    var isGateway: Bool = false

    // Read from the kernel ARP cache (ARPTable) after the host has been
    // probed. macVendor is derived from the MAC's OUI prefix (MacVendorLookup).
    var macAddress: String?
    var macVendor: String?

    // Populated by an on-demand deep scan (DeepPortScanner + SecurityAnalyzer),
    // not by the initial subnet sweep.
    var portBanners: [Int: String] = [:]
    var findings: [SecurityFinding] = []
    var isCamera: Bool = false
    var cameraVendor: String?
    var isDeepScanned: Bool = false

    var displayName: String {
        bonjourName ?? hostname ?? macVendor ?? ipAddress
    }
}

/// Ports the app knows how to label — covers both the fast initial sweep and
/// the wider list probed by DeepPortScanner.
enum WellKnownPort: Int, CaseIterable {
    case ftp = 21
    case ssh = 22
    case telnet = 23
    case smtp = 25
    case dns = 53
    case http = 80
    case pop3 = 110
    case rpc = 135
    case netbios = 139
    case imap = 143
    case https = 443
    case smb = 445
    case rtsp = 554
    case ipp = 631
    case mssql = 1433
    case telnetAlt = 2323
    case mysql = 3306
    case rdp = 3389
    case upnp = 5000
    case sip = 5060
    case postgres = 5432
    case vnc = 5900
    case redis = 6379
    case airplay = 7000
    case httpAlt1 = 8000
    case altHttp = 8080
    case httpAlt2 = 8081
    case httpsAlt = 8443
    case rtspAlt = 8554
    case httpAlt3 = 8888
    case rawPrinter = 9100
    case mongodb = 27017
    case dvr = 34567
    case dahua1 = 37777
    case dahua2 = 37778
    case lockdown = 62078 // iOS device services

    var label: String {
        switch self {
        case .ftp: return "FTP"
        case .ssh: return "SSH"
        case .telnet: return "Telnet"
        case .smtp: return "SMTP"
        case .dns: return "DNS"
        case .http: return "HTTP"
        case .pop3: return "POP3"
        case .rpc: return "RPC"
        case .netbios: return "NetBIOS"
        case .imap: return "IMAP"
        case .https: return "HTTPS"
        case .smb: return "SMB"
        case .rtsp: return "RTSP (камера)"
        case .ipp: return "IPP (Принтер)"
        case .mssql: return "MSSQL"
        case .telnetAlt: return "Telnet (alt)"
        case .mysql: return "MySQL"
        case .rdp: return "RDP"
        case .upnp: return "UPnP"
        case .sip: return "SIP"
        case .postgres: return "PostgreSQL"
        case .vnc: return "VNC"
        case .redis: return "Redis"
        case .airplay: return "AirPlay"
        case .httpAlt1: return "HTTP (камера/DVR)"
        case .altHttp: return "HTTP (alt)"
        case .httpAlt2: return "HTTP (alt)"
        case .httpsAlt: return "HTTPS (alt)"
        case .rtspAlt: return "RTSP (alt)"
        case .httpAlt3: return "HTTP (alt)"
        case .rawPrinter: return "Принтер (RAW)"
        case .mongodb: return "MongoDB"
        case .dvr: return "DVR/NVR"
        case .dahua1: return "Dahua DVR"
        case .dahua2: return "Dahua DVR (alt)"
        case .lockdown: return "iOS device"
        }
    }
}
