import Foundation
import NetworkExtension

/// Reads info about the Wi-Fi network the device is *currently* connected to
/// via NEHotspotNetwork (requires the "Access WiFi Information" entitlement,
/// no location permission needed). iOS does NOT expose which encryption
/// protocol is in use (WEP vs WPA2 vs WPA3) to third-party apps — only
/// whether the network is secured at all (`isSecure`). A full scan of
/// *surrounding* networks (like Fing/a real Wi-Fi analyzer does) is not
/// possible on stock iOS without a jailbreak: there is no public API for it.
enum WiFiSecurityInfo {
    struct CurrentNetwork {
        let ssid: String
        let bssid: String
        let isSecure: Bool
    }

    static func fetchCurrent() async -> CurrentNetwork? {
        await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                guard let network else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: CurrentNetwork(
                    ssid: network.ssid,
                    bssid: network.bssid,
                    isSecure: network.isSecure
                ))
            }
        }
    }
}

/// Tracks which BSSID (access point hardware address) each SSID has been
/// seen on before, on this device. If a known SSID suddenly shows up on a
/// BSSID we've never seen for it, that's the signature of an "evil twin" —
/// a rogue AP broadcasting the same network name to intercept traffic.
/// Persisted locally only; nothing leaves the device.
enum WiFiHistoryStore {
    private static let key = "wifi_history_ssid_to_bssids"

    private static func load() -> [String: Set<String>] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return decoded.mapValues { Set($0) }
    }

    private static func save(_ history: [String: Set<String>]) {
        let encodable = history.mapValues { Array($0) }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Returns true if this SSID has been seen before on a *different* BSSID
    /// than the one passed in (i.e. a possible evil twin), then records the
    /// current BSSID as known-good for next time.
    static func checkAndRecord(ssid: String, bssid: String) -> Bool {
        guard !ssid.isEmpty, !bssid.isEmpty else { return false }
        var history = load()
        let known = history[ssid] ?? []
        let isSuspicious = !known.isEmpty && !known.contains(bssid)
        history[ssid, default: []].insert(bssid)
        save(history)
        return isSuspicious
    }
}
