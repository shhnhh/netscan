import Foundation

/// Swift-friendly async wrapper over the Objective-C `ARPTable` reader.
/// Reads the whole cache in one shot (cheaper than one lookup per host) off
/// the main thread, and pairs each MAC with a best-effort vendor name.
enum ARPResolver {
    struct Entry {
        let mac: String
        let vendor: String?
    }

    static func snapshot() async -> [String: Entry] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String: Entry], Never>) in
            DispatchQueue.global(qos: .utility).async {
                let raw = ARPTable.currentTable()
                var result: [String: Entry] = [:]
                for (ip, mac) in raw {
                    result[ip] = Entry(mac: mac, vendor: MacVendorLookup.vendor(for: mac))
                }
                continuation.resume(returning: result)
            }
        }
    }
}
