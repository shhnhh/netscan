import Foundation

enum FindingSeverity: Int, Comparable, Hashable {
    case info = 0
    case warning = 1
    case critical = 2

    static func < (lhs: FindingSeverity, rhs: FindingSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .info: return "Инфо"
        case .warning: return "Внимание"
        case .critical: return "Критично"
        }
    }
}

/// A single rule-based observation produced by SecurityAnalyzer from open
/// ports and grabbed banners. Purely descriptive — the app never acts on a
/// finding (no auto-login, no exploitation), it only surfaces it to the user.
struct SecurityFinding: Identifiable, Hashable {
    let id = UUID()
    let severity: FindingSeverity
    let title: String
    let detail: String
    let port: Int?
}
