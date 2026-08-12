import Foundation
import CryptoKit

/// Checks a password against the "Have I Been Pwned" Pwned Passwords range
/// API using k-anonymity: only the first 5 hex chars of the SHA-1 hash are
/// ever sent over the network, never the password itself or its full hash.
/// No API key required, no backend needed.
enum PasswordBreachChecker {
    enum CheckError: Error {
        case network
        case badResponse
    }

    struct Result {
        let timesSeen: Int
        var isBreached: Bool { timesSeen > 0 }
    }

    static func check(password: String) async throws -> Result {
        let digest = Insecure.SHA1.hash(data: Data(password.utf8))
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        let prefix = String(hex.prefix(5))
        let suffix = String(hex.dropFirst(5))

        var request = URLRequest(url: URL(string: "https://api.pwnedpasswords.com/range/\(prefix)")!)
        request.setValue("true", forHTTPHeaderField: "Add-Padding")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CheckError.network
        }
        guard let body = String(data: data, encoding: .utf8) else {
            throw CheckError.badResponse
        }

        for line in body.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":")
            guard parts.count == 2, parts[0] == suffix, let count = Int(parts[1]) else { continue }
            return Result(timesSeen: count)
        }
        return Result(timesSeen: 0)
    }
}
