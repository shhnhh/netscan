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
    case networkGear
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
        case .networkGear: return "Сетевое оборудование"
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
        case .networkGear: return "wifi.router.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum PlatformGuesser {
    static func guess(for device: Device) -> DevicePlatform {
        let name = (device.bonjourName ?? device.hostname ?? "").lowercased()
        let ports = Set(device.openPorts)
        let vendor = device.macVendor
        // A device that answered SSDP discovery is running some UPnP
        // service — real phones/laptops normally don't, so this is a good
        // extra signal for disambiguating vendors that ship both TVs and
        // handsets (Samsung, Sony, LG).
        let respondsToSSDP = device.ssdpLocation != nil

        // Distinctive console product names beat everything else, including
        // the printer-port check below (a console can have odd open ports).
        if name.contains("xbox") {
            return .gameConsole
        }
        if name.contains("playstation") || name.contains("ps4") || name.contains("ps5") {
            return .gameConsole
        }

        // Printer ports are distinctive enough to check next — IPP (631)
        // and raw/JetDirect (9100) aren't used for much else on a LAN.
        if ports.contains(631) || ports.contains(9100)
            || name.contains("printer") || name.contains("принтер") {
            return .printer
        }

        // Router/AP/switch vendors ship almost nothing else that would show
        // up in a LAN scan, so this is unambiguous on its own.
        switch vendor {
        case "TP-Link", "Netgear", "D-Link", "Ubiquiti", "ASUS", "Keenetic", "Zyxel", "MikroTik":
            return .networkGear
        case "Espressif", "Raspberry Pi", "Tuya":
            return .iot
        case "Nintendo":
            return .gameConsole
        case "Apple":
            return .apple
        default:
            break
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
        let hasCastPorts = ports.contains(7000) || ports.contains(8008) || ports.contains(8009)
        if hasCastPorts
            || name.contains("tv") || name.contains("roku") || name.contains("chromecast")
            || name.contains("projector") || name.contains("проектор") || name.contains("epson")
            || name.contains("benq") {
            return .mediaDevice
        }
        // Samsung/Sony/LG all ship phones/speakers/appliances alongside
        // TVs, so only trust the vendor for "TV" once it's also answering
        // UPnP discovery — otherwise a bare vendor match is too likely to
        // be a phone.
        if respondsToSSDP, let vendor, ["Samsung", "Sony", "LG"].contains(vendor) {
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

        // Lower-confidence vendor fallbacks — these makers span several
        // device categories, so only use them once name/port/SSDP checks
        // above found nothing more specific.
        switch vendor {
        case "Amazon":
            // Echo speakers vastly outnumber Fire TVs in a typical OUI
            // block; a Fire TV would usually have already matched the
            // cast-port/name check above.
            return .iot
        case "Google":
            // Chromecasts/Google TV already matched hasCastPorts above;
            // what's left in this vendor block is mostly Nest/Home IoT.
            return .iot
        case "Xiaomi", "Huawei":
            return .android
        case "Microsoft":
            return .windows
        default:
            break
        }
        return .unknown
    }
}
