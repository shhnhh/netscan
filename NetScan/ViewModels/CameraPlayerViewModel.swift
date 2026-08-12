import Foundation
import SwiftUI
import UIKit

@MainActor
final class CameraPlayerViewModel: ObservableObject {
    @Published private(set) var currentFrame: UIImage?
    @Published private(set) var isConnected = false
    @Published private(set) var errorMessage: String?

    private let decoder = MJPEGStreamDecoder()

    init() {
        decoder.onFrame = { [weak self] image in
            Task { @MainActor in self?.currentFrame = image }
        }
        decoder.onConnected = { [weak self] in
            Task { @MainActor in
                self?.isConnected = true
                self?.errorMessage = nil
            }
        }
        decoder.onError = { [weak self] message in
            Task { @MainActor in
                self?.isConnected = false
                self?.errorMessage = message
            }
        }
    }

    func start(url: URL, username: String?, password: String?) {
        errorMessage = nil
        decoder.start(url: url, username: username, password: password)
    }

    func stop() {
        decoder.stop()
        isConnected = false
    }
}
