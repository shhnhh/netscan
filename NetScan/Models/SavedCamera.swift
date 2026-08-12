import Foundation

/// A camera the user has manually added by URL. The password never lives
/// here — it's kept in the Keychain, looked up by `id`, so it doesn't ride
/// along in plain UserDefaults/JSON.
struct SavedCamera: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var streamURLString: String
    var username: String?

    init(id: UUID = UUID(), name: String, streamURLString: String, username: String? = nil) {
        self.id = id
        self.name = name
        self.streamURLString = streamURLString
        self.username = username
    }
}
