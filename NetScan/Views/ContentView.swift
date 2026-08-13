import SwiftUI

private enum ContentRoute: Hashable {
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
                if !viewModel.isScanning && !viewModel.devices.isEmpty {
                    if viewModel.devicesWithIssues > 0 {
                        Label("\(viewModel.devicesWithIssues) \(Self.deviceWord(viewModel.devicesWithIssues)) с потенциальными проблемами",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label("Явных проблем безопасности не найдено",
                              systemImage: "checkmark.shield.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
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
                case .speedTest:
                    SpeedTestView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 18) {
                        NavigationLink(value: ContentRoute.speedTest) {
                            Image(systemName: "speedometer")
                        }
                        if !viewModel.isScanning && !viewModel.devices.isEmpty {
                            ShareLink(item: viewModel.reportText) {
                                Image(systemName: "square.and.arrow.up")
                            }
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

extension ContentView {
    static func deviceWord(_ n: Int) -> String {
        let mod100 = n % 100
        let mod10 = n % 10
        if (11...14).contains(mod100) { return "устройств" }
        if mod10 == 1 { return "устройство" }
        if (2...4).contains(mod10) { return "устройства" }
        return "устройств"
    }
}

#Preview {
    ContentView()
}
