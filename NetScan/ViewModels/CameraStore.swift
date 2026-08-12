import Foundation
import SwiftUI

@MainActor
final class CameraStore: ObservableObject {
    @Published private(set) var cameras: [SavedCamera] = []

    private let defaultsKey = "netscan.savedCameras"

    init() {
        load()
    }

    func add(_ camera: SavedCamera, password: String?) {
        cameras.append(camera)
        save()
        if let password, !password.isEmpty {
            KeychainStore.set(password, forKey: camera.id.uuidString)
        }
    }

    func remove(at offsets: IndexSet) {
        for index in offsets {
            KeychainStore.delete(forKey: cameras[index].id.uuidString)
        }
        cameras.remove(atOffsets: offsets)
        save()
    }

    func password(for camera: SavedCamera) -> String? {
        KeychainStore.get(forKey: camera.id.uuidString)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([SavedCamera].self, from: data) else { return }
        cameras = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cameras) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
