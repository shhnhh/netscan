import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ScannerViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let status = viewModel.statusMessage {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.devices) { device in
                    NavigationLink(value: device) {
                        DeviceRow(device: device)
                    }
                }
            }
            .navigationTitle("Устройства в сети")
            .navigationDestination(for: Device.self) { device in
                DeviceDetailView(device: device)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        NetworkMapView(devices: viewModel.devices)
                    } label: {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isScanning {
                        ProgressView()
                    } else {
                        Button("Сканировать") {
                            viewModel.startScan()
                        }
                    }
                }
            }
            .onAppear {
                if viewModel.devices.isEmpty {
                    viewModel.startScan()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
