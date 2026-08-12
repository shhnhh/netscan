import Foundation
import SwiftUI

@MainActor
final class SpeedTestViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle, ping, download, upload, done
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pingMs: Double?
    @Published private(set) var downloadMbps: Double?
    @Published private(set) var uploadMbps: Double?
    @Published private(set) var errorMessage: String?

    private let service = SpeedTestService()

    var isRunning: Bool {
        phase != .idle && phase != .done
    }

    func start() {
        guard !isRunning else { return }
        pingMs = nil
        downloadMbps = nil
        uploadMbps = nil
        errorMessage = nil

        Task {
            phase = .ping
            pingMs = await service.measurePing()

            phase = .download
            downloadMbps = await service.measureDownload()

            phase = .upload
            uploadMbps = await service.measureUpload()

            phase = .done
            if pingMs == nil, downloadMbps == nil, uploadMbps == nil {
                errorMessage = "Не получилось подключиться к серверу теста. Проверь интернет."
            }
        }
    }
}
