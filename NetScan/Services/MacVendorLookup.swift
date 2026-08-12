import Foundation

/// Maps a MAC address to its hardware vendor via the OUI (the first three
/// octets, assigned to manufacturers by the IEEE). This is exactly what Fing
/// shows as "MAC vendor".
///
/// The full IEEE OUI registry is ~35k entries / several MB; bundling all of
/// it isn't worth the size here. This is a curated set of the prefixes that
/// actually show up on home/office networks (phones, routers, IoT, consoles,
/// printers). A known MAC with an unlisted OUI just returns nil — that means
/// "vendor not in our table", not an error, and the table is easy to extend.
enum MacVendorLookup {
    static func vendor(for mac: String) -> String? {
        let normalized = mac.uppercased()
        guard normalized.count >= 8 else { return nil }
        let oui = String(normalized.prefix(8)) // "AA:BB:CC"
        return ouiTable[oui]
    }

    private static let ouiTable: [String: String] = [
        // Apple
        "A4:83:E7": "Apple", "F0:18:98": "Apple", "3C:15:C2": "Apple",
        "88:66:5A": "Apple", "AC:BC:32": "Apple", "F4:0F:24": "Apple",
        "90:B0:ED": "Apple", "DC:2B:2A": "Apple", "D0:23:DB": "Apple",
        "68:A8:6D": "Apple", "7C:6D:62": "Apple", "B8:78:2E": "Apple",
        "5C:59:48": "Apple", "E4:CE:8F": "Apple", "F8:1E:DF": "Apple",
        "28:CF:E9": "Apple", "1C:AB:A7": "Apple", "84:38:35": "Apple",
        // Samsung
        "08:37:3D": "Samsung", "34:BE:00": "Samsung", "5C:0A:5B": "Samsung",
        "78:1F:DB": "Samsung", "8C:77:12": "Samsung", "B4:07:F9": "Samsung",
        "C8:19:F7": "Samsung", "E8:50:8B": "Samsung", "F0:08:F1": "Samsung",
        "38:AA:3C": "Samsung", "1C:62:B8": "Samsung", "D0:59:E4": "Samsung",
        // Intel
        "04:EC:D8": "Intel", "3C:A9:F4": "Intel", "7C:B0:C2": "Intel",
        "8C:16:45": "Intel", "94:65:9C": "Intel", "A0:88:69": "Intel",
        "AC:7B:A1": "Intel", "B4:96:91": "Intel", "DC:53:60": "Intel",
        "34:13:E8": "Intel", "E4:A7:A0": "Intel",
        // Xiaomi
        "0C:1D:AF": "Xiaomi", "14:F6:5A": "Xiaomi", "28:6C:07": "Xiaomi",
        "3C:BD:3E": "Xiaomi", "50:8F:4C": "Xiaomi", "64:09:80": "Xiaomi",
        "7C:1D:D9": "Xiaomi", "98:FA:E3": "Xiaomi", "F0:B4:29": "Xiaomi",
        "F8:A4:5F": "Xiaomi", "8C:BE:BE": "Xiaomi",
        // Huawei / Honor
        "00:E0:FC": "Huawei", "04:BD:88": "Huawei", "18:C5:8A": "Huawei",
        "28:6E:D4": "Huawei", "48:46:FB": "Huawei", "70:72:3C": "Huawei",
        "9C:28:EF": "Huawei", "C8:51:95": "Huawei", "E0:24:7F": "Huawei",
        // TP-Link
        "14:CC:20": "TP-Link", "1C:3B:F3": "TP-Link", "30:B5:C2": "TP-Link",
        "50:C7:BF": "TP-Link", "60:32:B1": "TP-Link", "98:DA:C4": "TP-Link",
        "AC:84:C6": "TP-Link", "C0:06:C3": "TP-Link", "EC:08:6B": "TP-Link",
        "A4:2B:B0": "TP-Link", "F4:F2:6D": "TP-Link",
        // Google (Nest / Chromecast)
        "08:9E:08": "Google", "20:DF:B9": "Google", "3C:5A:B4": "Google",
        "54:60:09": "Google", "94:95:A0": "Google", "A4:77:33": "Google",
        "D8:6C:63": "Google", "F4:F5:D8": "Google", "F4:F5:E8": "Google",
        // Amazon (Echo / Fire)
        "0C:47:C9": "Amazon", "34:D2:70": "Amazon", "44:00:49": "Amazon",
        "68:37:E9": "Amazon", "74:C2:46": "Amazon", "84:D6:D0": "Amazon",
        "AC:63:BE": "Amazon", "F0:27:2D": "Amazon", "FC:65:DE": "Amazon",
        "40:B4:CD": "Amazon", "68:54:FD": "Amazon",
        // Espressif (ESP8266 / ESP32 — very common in DIY/IoT)
        "18:FE:34": "Espressif", "24:6F:28": "Espressif", "30:AE:A4": "Espressif",
        "3C:71:BF": "Espressif", "5C:CF:7F": "Espressif", "84:0D:8E": "Espressif",
        "84:F3:EB": "Espressif", "A4:CF:12": "Espressif", "B4:E6:2D": "Espressif",
        "CC:50:E3": "Espressif", "DC:4F:22": "Espressif", "EC:FA:BC": "Espressif",
        // Raspberry Pi
        "28:CD:C1": "Raspberry Pi", "B8:27:EB": "Raspberry Pi",
        "DC:A6:32": "Raspberry Pi", "E4:5F:01": "Raspberry Pi",
        // Tuya (smart plugs / bulbs / generic smart-home)
        "10:D5:61": "Tuya", "18:69:D8": "Tuya", "24:4C:AB": "Tuya",
        "50:02:91": "Tuya", "68:57:2D": "Tuya", "84:E3:42": "Tuya",
        "D8:1F:12": "Tuya", "FC:67:1F": "Tuya",
        // Microsoft (Xbox / Surface)
        "00:15:5D": "Microsoft", "0C:41:3E": "Microsoft", "28:18:78": "Microsoft",
        "3C:83:75": "Microsoft", "48:50:73": "Microsoft", "50:1A:C5": "Microsoft",
        "7C:1E:52": "Microsoft", "98:5F:D3": "Microsoft", "C8:3F:26": "Microsoft",
        // Sony (PlayStation / Bravia)
        "00:13:15": "Sony", "00:19:63": "Sony", "30:F9:ED": "Sony",
        "54:42:49": "Sony", "78:84:3C": "Sony", "A0:E4:53": "Sony",
        "AC:9B:0A": "Sony", "D8:D4:3C": "Sony", "FC:F1:52": "Sony",
        // LG
        "10:68:3F": "LG", "2C:54:CF": "LG", "3C:BD:D8": "LG",
        "58:A2:B5": "LG", "64:99:5D": "LG", "88:C9:D0": "LG",
        "A8:16:B2": "LG", "C4:36:6C": "LG", "CC:2D:8C": "LG",
        // Nintendo (Switch / Wii)
        "04:03:D6": "Nintendo", "18:2A:7B": "Nintendo", "34:AF:2C": "Nintendo",
        "58:BD:A3": "Nintendo", "78:A2:A0": "Nintendo", "8C:56:C5": "Nintendo",
        "98:B6:E9": "Nintendo", "9C:E6:35": "Nintendo", "E0:0C:7F": "Nintendo",
        // Netgear
        "20:0C:C8": "Netgear", "28:C6:8E": "Netgear", "2C:30:33": "Netgear",
        "44:94:FC": "Netgear", "6C:B0:CE": "Netgear", "9C:3D:CF": "Netgear",
        "A0:04:60": "Netgear", "C0:3F:0E": "Netgear", "CC:40:D0": "Netgear",
        // D-Link
        "1C:7E:E5": "D-Link", "28:10:7B": "D-Link", "5C:D9:98": "D-Link",
        "78:54:2E": "D-Link", "84:C9:B2": "D-Link", "90:94:E4": "D-Link",
        "AC:F1:DF": "D-Link", "C8:BE:19": "D-Link", "F0:7D:68": "D-Link",
        // Ubiquiti
        "00:15:6D": "Ubiquiti", "04:18:D6": "Ubiquiti", "24:A4:3C": "Ubiquiti",
        "44:D9:E7": "Ubiquiti", "68:72:51": "Ubiquiti", "78:8A:20": "Ubiquiti",
        "B4:FB:E4": "Ubiquiti", "DC:9F:DB": "Ubiquiti", "F0:9F:C2": "Ubiquiti",
        // ASUS
        "04:D4:C4": "ASUS", "2C:56:DC": "ASUS", "38:D5:47": "ASUS",
        "50:46:5D": "ASUS", "70:8B:CD": "ASUS", "AC:22:0B": "ASUS",
        "BC:EE:7B": "ASUS", "D8:50:E6": "ASUS", "F0:2F:74": "ASUS",
        // Keenetic / Zyxel (common in RU/CIS)
        "50:FF:20": "Keenetic", "54:47:1E": "Zyxel", "AC:9A:96": "Zyxel",
        "B0:B2:DC": "Zyxel", "5C:E2:8C": "Zyxel",
        // MikroTik
        "08:55:31": "MikroTik", "18:FD:74": "MikroTik", "48:8F:5A": "MikroTik",
        "64:D1:54": "MikroTik", "6C:3B:6B": "MikroTik", "74:4D:28": "MikroTik",
        "CC:2D:E0": "MikroTik", "DC:2C:6E": "MikroTik", "E4:8D:8C": "MikroTik",
    ]
}
