import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Устройства", systemImage: "network") }
            CamerasView()
                .tabItem { Label("Камеры", systemImage: "video.fill") }
        }
    }
}

#Preview {
    RootTabView()
}
