import Foundation

/// Small curated OUI (first 3 MAC bytes) → vendor table — not the full
/// ~40k-entry IEEE registry (that's a multi-megabyte download we don't have
/// a live source for here), just the manufacturers you actually run into on
/// a home/office LAN. Falls back to nil rather than guessing.
enum MacVendorLookup {
    private static let ouiTable: [String: String] = [
        "00:1A:11": "Google", "F4:F5:D8": "Google", "3C:5A:B4": "Google",
        "A4:77:33": "Google", "94:EB:2C": "Google",
        "AC:DE:48": "Apple", "F0:18:98": "Apple", "A4:83:E7": "Apple",
        "BC:52:B7": "Apple", "F4:5C:89": "Apple", "3C:22:FB": "Apple",
        "68:96:7B": "Apple", "DC:A9:04": "Apple", "88:66:A5": "Apple",
        "D0:03:4B": "Apple", "8C:85:90": "Apple", "04:1E:64": "Apple",
        "00:1B:63": "Apple", "28:F0:76": "Apple", "A8:5C:2C": "Apple",
        "70:56:81": "Apple", "C8:69:CD": "Apple", "5C:95:AE": "Apple",
        "34:36:3B": "Samsung", "5C:0A:5B": "Samsung", "8C:71:F8": "Samsung",
        "C0:BD:D1": "Samsung", "E8:50:8B": "Samsung", "AC:5F:3E": "Samsung",
        "3C:5A:37": "Samsung", "88:32:9B": "Samsung",
        "3C:D9:2B": "Hewlett Packard", "10:60:4B": "Hewlett Packard",
        "00:1F:29": "Hewlett Packard", "70:5A:0F": "Hewlett Packard",
        "00:50:56": "VMware", "00:0C:29": "VMware", "00:1C:14": "VMware",
        "B8:27:EB": "Raspberry Pi Foundation", "DC:A6:32": "Raspberry Pi Foundation",
        "D8:3A:DD": "Raspberry Pi Foundation", "E4:5F:01": "Raspberry Pi Foundation",
        "18:FE:34": "Espressif (ESP8266/32 IoT)", "24:6F:28": "Espressif (ESP8266/32 IoT)",
        "30:AE:A4": "Espressif (ESP8266/32 IoT)", "A4:CF:12": "Espressif (ESP8266/32 IoT)",
        "CC:50:E3": "Espressif (ESP8266/32 IoT)", "3C:71:BF": "Espressif (ESP8266/32 IoT)",
        "EC:FA:BC": "TP-Link", "50:C7:BF": "TP-Link", "F4:F2:6D": "TP-Link",
        "AC:84:C6": "TP-Link", "98:DA:C4": "TP-Link", "C4:6E:1F": "TP-Link",
        "00:14:BF": "Cisco", "00:1B:D4": "Cisco", "58:97:1E": "Cisco",
        "00:26:99": "Cisco", "00:0F:66": "Cisco",
        "18:D6:C7": "MikroTik", "4C:5E:0C": "MikroTik", "6C:3B:6B": "MikroTik",
        "1C:69:7A": "Dahua", "3C:EF:8C": "Dahua", "D4:63:C6": "Dahua",
        "44:19:B6": "Hikvision", "28:57:BE": "Hikvision", "4C:BD:8F": "Hikvision",
        "38:33:B5": "Ubiquiti", "24:5A:4C": "Ubiquiti", "78:8A:20": "Ubiquiti",
        "FC:EC:DA": "Ubiquiti", "F0:9F:C2": "Ubiquiti",
        "00:11:32": "Synology", "00:24:1D": "Synology",
        "00:09:0F": "Fortinet", "70:4C:A5": "Fortinet",
        "44:D9:E7": "Amazon", "68:37:E9": "Amazon", "F0:27:2D": "Amazon",
        "AC:63:BE": "Amazon", "50:DC:E7": "Xiaomi", "78:11:DC": "Xiaomi",
        "64:CC:2E": "Xiaomi", "34:CE:00": "Xiaomi",
        "A4:5E:60": "Intel", "3C:A9:F4": "Intel", "00:1B:21": "Intel",
        "F8:63:3F": "Intel", "94:65:2D": "Intel",
    ]

    static func vendor(forMac mac: String) -> String? {
        let prefix = mac.split(separator: ":").prefix(3).joined(separator: ":").uppercased()
        return ouiTable[prefix]
    }
}
