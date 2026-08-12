import SwiftUI

private enum ContentRoute: Hashable {
    case map
    case speedTest
}

struct ContentView: View {
    @StateObject private var viewModel = ScannerViewModel()

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isScanning {
                    HStack {
                        Text("Сканирую… \(viewModel.scannedCount)/\(viewModel.totalHosts)")
                        Spacer()
                        Text("Найдено: \(viewModel.devices.count)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let status = viewModel.statusMessage {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.devices) { device in
                    NavigationLink(value: device) {
                        DeviceRow(device: device)
                    }
                }
            }
            .navigationTitle(viewModel.devices.isEmpty ? "Устройства в сети" : "Устройства (\(viewModel.devices.count))")
            .navigationDestination(for: Device.self) { device in
                DeviceDetailView(device: device)
            }
            .navigationDestination(for: ContentRoute.self) { route in
                switch route {
                case .map:
                    NetworkMapView(devices: viewModel.devices)
                case .speedTest:
                    SpeedTestView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 18) {
                        NavigationLink(value: ContentRoute.map) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                        }
                        NavigationLink(value: ContentRoute.speedTest) {
                            Image(systemName: "speedometer")
                        }
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
