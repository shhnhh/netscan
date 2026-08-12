import Foundation

/// Best-effort OS/platform guess from what we can actually see on iOS —
/// open ports, Bonjour/hostname strings. No TTL fingerprinting, no ARP
/// vendor-based OS inference like Fing does with a full OUI database on a
/// desktop OS; this is deliberately coarse.
enum DevicePlatform {
    case apple
    case windows
    case android
    case unknown

    var label: String {
        switch self {
        case .apple: return "Apple"
        case .windows: return "Windows"
        case .android: return "Android"
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
        case .unknown: return "questionmark.circle"
        }
    }
}

enum PlatformGuesser {
    static func guess(for device: Device) -> DevicePlatform {
        let name = (device.bonjourName ?? device.hostname ?? "").lowercased()
        let ports = Set(device.openPorts)

        if name.contains("iphone") || name.contains("ipad") || name.contains("macbook")
            || name.contains("imac") || name.contains("mac mini") || name.contains("mac pro")
            || name.contains("apple tv") || name.contains(" mac") || name.hasPrefix("mac")
            || ports.contains(62078) || ports.contains(7000) {
            return .apple
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
