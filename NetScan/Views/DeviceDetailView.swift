import SwiftUI

struct DeviceDetailView: View {
    @StateObject private var viewModel: DeviceDetailViewModel

    init(device: Device) {
        _viewModel = StateObject(wrappedValue: DeviceDetailViewModel(device: device))
    }

    private var device: Device { viewModel.device }

    var body: some View {
        List {
            Section("Информация") {
                LabeledContent("IP-адрес", value: device.ipAddress)
                if let hostname = device.hostname {
                    LabeledContent("Имя хоста", value: hostname)
                }
                if let bonjour = device.bonjourName {
                    LabeledContent("Bonjour", value: bonjour)
                }
                if let ms = device.responseTimeMs {
                    LabeledContent("Отклик", value: "\(Int(ms)) ms")
                }
                if device.isCamera {
                    Label(
                        device.cameraVendor.map { "Похоже на камеру (\($0))" } ?? "Похоже на камеру/видеорегистратор",
                        systemImage: "video.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    viewModel.runDeepScan()
                } label: {
                    HStack {
                        if viewModel.isDeepScanning {
                            ProgressView()
                            Text("Сканирую порты и баннеры…")
                        } else {
                            Image(systemName: "shield.lefthalf.filled")
                            Text(device.isDeepScanned ? "Пересканировать" : "Глубокое сканирование (порты + уязвимости)")
                        }
                    }
                }
                .disabled(viewModel.isDeepScanning)
            } footer: {
                Text("Проверяет расширенный список портов и баннеры сервисов этого устройства. Только пассивное чтение — без подбора паролей и подключения к найденным сервисам.")
            }

            if !device.findings.isEmpty {
                Section("Проблемы безопасности") {
                    ForEach(device.findings) { finding in
                        FindingRow(finding: finding)
                    }
                }
            }

            Section("Открытые порты") {
                if device.openPorts.isEmpty {
                    Text("Не обнаружены")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(device.openPorts, id: \.self) { port in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("\(port)")
                                if let known = WellKnownPort(rawValue: port) {
                                    Text(known.label)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            if let banner = device.portBanners[port] {
                                Text(banner.split(separator: "\n").first.map(String.init) ?? banner)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(device.displayName)
    }
}

private struct FindingRow: View {
    let finding: SecurityFinding

    private var color: Color {
        switch finding.severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private var symbol: String {
        switch finding.severity {
        case .critical: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(finding.title, systemImage: symbol)
                .foregroundStyle(color)
                .font(.subheadline.bold())
            Text(finding.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        DeviceDetailView(device: Device(id: "192.168.1.1", ipAddress: "192.168.1.1"))
    }
}
