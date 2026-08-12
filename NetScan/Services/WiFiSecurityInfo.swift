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

    /// There are known iOS bugs/quirks (reported on Apple's own developer
    /// forums) where fetchCurrent()'s completion handler simply never fires
    /// — without a timeout, that hangs this whole call, and the caller's UI,
    /// forever with no feedback. Capped so it always resolves one way or
    /// another within a few seconds.
    private static let fetchTimeout: TimeInterval = 5

    static func fetchCurrent() async -> FetchOutcome {
        let locationGranted = await LocationAuthorizer.shared.ensureAuthorized()

        let network = await withCheckedContinuation { (continuation: CheckedContinuation<CurrentNetwork?, Never>) in
            var resumed = false
            let resumeOnce: (CurrentNetwork?) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }

            NEHotspotNetwork.fetchCurrent { network in
                guard let network else {
                    resumeOnce(nil)
                    return
                }
                resumeOnce(CurrentNetwork(
                    ssid: network.ssid,
                    bssid: network.bssid,
                    isSecure: network.isSecure
                ))
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + fetchTimeout) {
                resumeOnce(nil)
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
///
/// Deliberately does NOT wait on the CLLocationManagerDelegate callback to
/// find out when the user has answered the system prompt — there are
/// reports of that callback not firing reliably, and there's no reliable
/// way to tell "still waiting on the delegate" apart from "waiting on the
/// user to tap something in the system alert" from inside the app process.
/// Polling `authorizationStatus` directly sidesteps both problems: it picks
/// up the answer the moment it's set regardless of whether the delegate
/// fires, and the loop only ends the wait, it never blocks the human from
/// taking their time on the actual system dialog.
final class LocationAuthorizer: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuthorizer()

    /// 120 * 0.5s = 60s total — generous for a human decision, but still
    /// bounded so a genuinely broken permission flow resolves instead of
    /// hanging the caller (and its "Проверяю…" spinner) forever.
    private static let maxPolls = 120
    private static let pollInterval: UInt64 = 500_000_000

    private let manager = CLLocationManager()

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

        manager.requestWhenInUseAuthorization()

        for _ in 0..<Self.maxPolls {
            try? await Task.sleep(nanoseconds: Self.pollInterval)
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
                return true
            case .denied, .restricted:
                return false
            case .notDetermined:
                continue
            @unknown default:
                return false
            }
        }
        return false
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
