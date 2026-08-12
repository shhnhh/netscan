import SwiftUI

struct CamerasView: View {
    @StateObject private var store = CameraStore()
    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                if store.cameras.isEmpty {
                    Text("Пока нет добавленных камер. Жми + и добавь свою по URL.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.cameras) { camera in
                    NavigationLink {
                        CameraPlayerView(camera: camera, password: store.password(for: camera))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(camera.name)
                            Text(camera.streamURLString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { store.remove(at: $0) }
            }
            .navigationTitle("Мои камеры")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddCameraView(store: store)
            }
        }
    }
}

#Preview {
    CamerasView()
}
