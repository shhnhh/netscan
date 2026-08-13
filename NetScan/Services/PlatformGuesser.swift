import Foundation

/// Best-effort OS/platform guess from what we can actually see on iOS —
/// open ports, Bonjour/hostname strings. No TTL fingerprinting, no ARP
/// vendor-based OS inference like Fing does with a full OUI database on a
/// desktop OS; this is deliberately coarse.
enum DevicePlatform: Equatable {
    case apple
    case windows
    case android
    case printer
    case mediaDevice
    case iot
    case gameConsole
    case unknown

    var label: String {
        switch self {
        case .apple: return "Apple"
        case .windows: return "Windows"
        case .android: return "Android"
        case .printer: return "Принтер"
        case .mediaDevice: return "ТВ/проектор"
        case .iot: return "IoT/умный дом"
        case .gameConsole: return "Игровая консоль"
        case .unknown: return "Неизвестно"
        }
    }

    /// SF Symbols has Apple's own logo built in, but no Windows/Android
    /// trademarked logos (Apple doesn't ship competitors' marks) — these are
    /// the closest neutral stand-ins.
    var symbolName: String {
        switch self {
        case .apple: return "apple.logo"
        case .windows: return "pc"
        case .android: return "smartphone"
        case .printer: return "printer.fill"
        case .mediaDevice: return "tv.fill"
        case .iot: return "sensor.fill"
        case .gameConsole: return "gamecontroller.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum PlatformGuesser {
    static func guess(for device: Device) -> DevicePlatform {
        let name = (device.bonjourName ?? device.hostname ?? "").lowercased()
        let ports = Set(device.openPorts)
        let vendor = device.macVendor

        // The MAC vendor, when we have it, is a stronger signal than port
        // guessing for a few unambiguous makers — check those first.
        switch vendor {
        case "Espressif", "Raspberry Pi", "Tuya":
            return .iot
        case "Nintendo":
            return .gameConsole
        case "Apple":
            return .apple
        default:
            break
        }

        // Printer ports are distinctive enough to check first — IPP (631)
        // and raw/JetDirect (9100) aren't used for much else on a LAN.
        if ports.contains(631) || ports.contains(9100)
            || name.contains("printer") || name.contains("принтер") {
            return .printer
        }
        if name.contains("iphone") || name.contains("ipad") || name.contains("macbook")
            || name.contains("imac") || name.contains("mac mini") || name.contains("mac pro")
            || name.contains("apple tv") || name.contains(" mac") || name.hasPrefix("mac")
            || ports.contains(62078) {
            return .apple
        }
        // Port 7000 is the AirPlay *receiver* port — opened by things you
        // cast/mirror to (TVs, projectors, speakers, AppleTV), not by
        // phones/Macs initiating a cast. If the name didn't already say
        // "Apple TV" above, this is more likely a third-party TV/projector
        // with AirPlay support than an actual Apple device. Chromecast
        // receivers use 8008/8009 the same way.
        if ports.contains(7000) || ports.contains(8008) || ports.contains(8009)
            || name.contains("tv") || name.contains("roku") || name.contains("chromecast")
            || name.contains("projector") || name.contains("проектор") || name.contains("epson")
            || name.contains("benq") {
            return .mediaDevice
        }
        if name.contains("android") || name.contains("galaxy") || name.contains("pixel")
            || name.contains("redmi") || name.contains("xiaomi") || name.contains("huawei")
            || name.contains("oneplus") {
            return .android
        }
        if name.contains("desktop-") || name.contains("-pc") || name.contains("windows")
            || (ports.contains(3389) && !ports.contains(62078))
            || (ports.contains(139) && ports.contains(445)) {
            return .windows
        }
        return .unknown
    }
}
