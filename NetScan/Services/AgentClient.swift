import Foundation

/// Talks to the optional companion `netscan-agent.py` script (see /agent in
/// the repo) running on some other always-on machine on the LAN. That
/// script isn't sandboxed the way iOS is, so it can read the OS's real ARP
/// table and hand back actual MAC addresses instead of the
/// 02:00:00:00:00:00 placeholder iOS enforces for third-party apps here —
/// the same role Fing's Desktop/Agent components play for their mobile
/// app, just as a single self-hosted script instead of a separate product.
enum AgentClient {
    struct Entry {
        let mac: String
        let vendor: String?
    }

    /// Queries the agent's `/arp` endpoint. Always best-effort: an empty
    /// dictionary comes back (never a thrown error) if the agent isn't
    /// configured, unreachable, or its response doesn't parse — this is a
    /// supplement to the on-device ARP read, never a requirement for the
    /// app to function.
    static func fetchARPTable(baseURL: String, token: String, timeout: TimeInterval = 3) async -> [String: Entry] {
        guard var url = URL(string: baseURL) else { return [:] }
        url.appendPathComponent("arp")

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        var result: [String: Entry] = [:]
        for (ip, mac) in raw {
            result[ip] = Entry(mac: mac, vendor: MacVendorLookup.vendor(for: mac))
        }
        return result
    }
}
