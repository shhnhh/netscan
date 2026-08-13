import Foundation

/// Persists the optional LAN agent's connection details (see AgentClient).
/// Small enough that a plain UserDefaults wrapper is simpler than pulling
/// in a settings framework — and it's the same storage @AppStorage in
/// AgentSettingsView reads/writes, keyed by these exact strings.
enum AgentSettings {
    static let enabledKey = "netscan.agent.enabled"
    static let hostKey = "netscan.agent.host"
    static let tokenKey = "netscan.agent.token"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var host: String {
        UserDefaults.standard.string(forKey: hostKey) ?? ""
    }

    static var token: String {
        UserDefaults.standard.string(forKey: tokenKey) ?? ""
    }

    /// The configured host, normalized into a base URL string — accepts
    /// either "192.168.1.50:8756" or a fully-qualified "http://..." so
    /// users don't have to remember to type the scheme. Returns nil when
    /// nothing's configured, so callers can skip the agent entirely.
    static var baseURL: String? {
        normalizeBaseURL(host)
    }

    static func normalizeBaseURL(_ rawHost: String) -> String? {
        let trimmed = rawHost.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        return "http://\(trimmed)"
    }
}
