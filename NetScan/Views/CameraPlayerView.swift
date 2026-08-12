import SwiftUI

struct CameraPlayerView: View {
    let camera: SavedCamera
    let password: String?

    @StateObject private var viewModel = CameraPlayerViewModel()

    var body: some View {
        VStack {
            if let image = viewModel.currentFrame {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding()
            } else {
                ProgressView("Подключаюсь…")
            }
        }
        .navigationTitle(camera.name)
        .onAppear {
            if let url = URL(string: camera.streamURLString) {
                viewModel.start(url: url, username: camera.username, password: password)
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

#Preview {
    NavigationStack {
        CameraPlayerView(
            camera: SavedCamera(name: "Тест", streamURLString: "http://192.168.1.50/mjpg/video.mjpg"),
            password: nil
        )
    }
}
