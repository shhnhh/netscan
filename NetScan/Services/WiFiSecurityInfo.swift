import Foundation
import CoreLocation
import NetworkExtension

/// Reads info about the Wi-Fi network the device is *currently* connected to
/// via NEHotspotNetwork. Per Apple (developer.apple.com/forums/thread/684519),
/// fetchCurrent() only returns data if the app holds the "Access WiFi
/// Information" entitlement AND meets one of: active CoreLocation
/// "when in use" authorization, an NEHotspotConfiguration for this network,
/// an active VPN, or an active NEDNSSettingsManager config. The entitlement
/// alone is not enough — we also need the CoreLocation half, handled by
/// LocationAuthorizer below. iOS does NOT expose which encryption protocol
/// is in use (WEP vs WPA2 vs WPA3) to third-party apps — only whether the
/// network is secured at all (`isSecure`). A full scan of *surrounding*
/// networks (like Fing/a real Wi-Fi analyzer does) is not possible on stock
/// iOS without a jailbreak: there is no public API for it.
enum WiFiSecurityInfo {
    struct CurrentNetwork {
        let ssid: String
        let bssid: String
        let isSecure: Bool
    }

    enum FetchOutcome {
        case success(CurrentNetwork)
        case locationPermissionDenied
        case unavailable
    }

    static func fetchCurrent() async -> FetchOutcome {
        let locationGranted = await LocationAuthorizer.shared.ensureAuthorized()

        let network = await withCheckedContinuation { (continuation: CheckedContinuation<CurrentNetwork?, Never>) in
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

        if let network {
            return .success(network)
        }
        return locationGranted ? .unavailable : .locationPermissionDenied
    }
}

/// NEHotspotNetwork.fetchCurrent() needs *active* CoreLocation "when in use"
/// authorization, not just the entitlement — just holding authorization
/// isn't reliably enough either, so this also fires a one-shot location
/// request after getting permission, since that's the pattern Apple's own
/// forum thread on this exact issue confirms works.
final class LocationAuthorizer: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuthorizer()

    private let manager = CLLocationManager()
    private var resumed = false
    private var continuation: CheckedContinuation<Bool, Never>?

    private override init() {
        super.init()
        manager.delegate = self
    }

    func ensureAuthorized() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            break
        @unknown default:
            return false
        }

        return await withCheckedContinuation { continuation in
            self.resumed = false
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !resumed, let continuation else { return }
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        resumed = true
        self.continuation = nil
        let granted = status == .authorizedWhenInUse || status == .authorizedAlways
        if granted { manager.requestLocation() }
        continuation.resume(returning: granted)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
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
