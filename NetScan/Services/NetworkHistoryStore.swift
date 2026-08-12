import Foundation

/// Remembers which devices (by MAC) have been seen on a given network before,
/// so a later scan can flag genuinely new arrivals — the "new device on your
/// network" signal Fing shows. Persisted locally in UserDefaults; nothing
/// leaves the device.
///
/// Keyed per network (the subnet's gateway address) so moving between Wi-Fi
/// networks doesn't make every device look new. MAC is the identity, not IP:
/// DHCP hands out different IPs over time, but the MAC of a given device is
/// stable within a network.
enum NetworkHistoryStore {
    private static let key = "network_history_seen_macs"

    private static func loadAll() -> [String: Set<String>] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return decoded.mapValues { Set($0) }
    }

    private static func saveAll(_ value: [String: Set<String>]) {
        let encodable = value.mapValues { Array($0) }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Whether we have any prior record for this network. On the very first
    /// scan of a network there's no baseline, so nothing should be called
    /// "new" — that first scan just establishes what's normally there.
    static func hasBaseline(network: String) -> Bool {
        !(loadAll()[network]?.isEmpty ?? true)
    }

    static func seenMacs(network: String) -> Set<String> {
        loadAll()[network] ?? []
    }

    /// Folds this scan's MACs into the network's known set.
    static func record(macs: Set<String>, network: String) {
        guard !network.isEmpty, !macs.isEmpty else { return }
        var all = loadAll()
        all[network, default: []].formUnion(macs)
        saveAll(all)
    }
}
