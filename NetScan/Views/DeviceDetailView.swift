import SwiftUI

struct DeviceDetailView: View {
    @StateObject private var viewModel: DeviceDetailViewModel

    init(device: Device) {
        _viewModel = StateObject(wrappedValue: DeviceDetailViewModel(device: device))
    }

    private var device: Device { viewModel.device }

    private var platform: DevicePlatform {
        PlatformGuesser.guess(for: device)
    }

    var body: some View {
        List {
            Section("Информация") {
                LabeledContent("IP-адрес", value: device.ipAddress)
                if device.isGateway {
                    Label("Роутер (шлюз сети)", systemImage: "wifi.router.fill")
                        .foregroundStyle(.blue)
                }
                if device.isNewDevice {
                    Label("Новое устройство в сети", systemImage: "sparkles")
                        .foregroundStyle(.green)
                }
                if let hostname = device.hostname {
                    LabeledContent("Имя хоста", value: hostname)
                }
                if let bonjour = device.bonjourName {
                    LabeledContent("Bonjour", value: bonjour)
                }
                if let mac = device.macAddress {
                    LabeledContent("MAC-адрес", value: mac)
                }
                if let vendor = device.macVendor {
                    LabeledContent("Производитель (по MAC)", value: vendor)
                }
                if platform != .unknown {
                    LabeledContent("Платформа (эвристика)", value: platform.label)
                }
                if let ms = device.responseTimeMs {
                    LabeledContent("Отклик (скан)", value: "\(Int(ms)) ms")
                }
                if device.isCamera {
                    Label(
                        device.cameraVendor.map { "Похоже на камеру (\($0))" } ?? "Похоже на камеру/видеорегистратор",
                        systemImage: "video.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section("Действия") {
                Button {
                    viewModel.runPing()
                } label: {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        if viewModel.isPinging {
                            Text("Пингую…")
                        } else if let ms = viewModel.lastPingMs {
                            Text("Пинг: \(Int(ms)) ms")
                        } else {
                            Text("Пинг")
                        }
                        Spacer()
                        if viewModel.isPinging { ProgressView() }
                    }
                }
                .disabled(viewModel.isPinging)

                if let url = viewModel.webUIURL {
                    Link(destination: url) {
                        HStack {
                            Image(systemName: "safari")
                            Text("Открыть веб-интерфейс")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if viewModel.canWake {
                    Button {
                        viewModel.wakeOnLAN()
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                            if let message = viewModel.wakeResultMessage {
                                Text(message)
                            } else {
                                Text("Разбудить (Wake-on-LAN)")
                            }
                            Spacer()
                            if viewModel.isWaking { ProgressView() }
                        }
                    }
                    .disabled(viewModel.isWaking)
                }

                if viewModel.canPrintTestPage {
                    Button {
                        viewModel.printTestPage()
                    } label: {
                        HStack {
                            Image(systemName: "printer.fill")
                            if let message = viewModel.printResultMessage {
                                Text(message)
                            } else {
                                Text("Напечатать тестовую страницу")
                            }
                            Spacer()
                            if viewModel.isPrintingTestPage { ProgressView() }
                        }
                    }
                    .disabled(viewModel.isPrintingTestPage)
                }
            }

            if viewModel.canControlMedia {
                MediaControlSection(viewModel: viewModel)
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

/// UPnP/DLNA transport controls — only meaningful once we know whether the
/// device actually exposes AVTransport/RenderingControl, which requires a
/// network round-trip to its SSDP description XML, so this fetches lazily
/// on first appearance rather than during the main scan.
private struct MediaControlSection: View {
    @ObservedObject var viewModel: DeviceDetailViewModel
    @State private var volume: Double = 50

    var body: some View {
        Section("Управление медиа (UPnP/DLNA)") {
            if viewModel.isLoadingUPnP {
                HStack {
                    ProgressView()
                    Text("Ищу элементы управления…")
                        .foregroundStyle(.secondary)
                }
            } else if let points = viewModel.upnpControlPoints {
                if points.hasAnyControl {
                    if points.avTransport != nil {
                        HStack(spacing: 24) {
                            Button {
                                viewModel.sendMediaAction(.play)
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            Button {
                                viewModel.sendMediaAction(.pause)
                            } label: {
                                Image(systemName: "pause.fill")
                            }
                            Button {
                                viewModel.sendMediaAction(.stop)
                            } label: {
                                Image(systemName: "stop.fill")
                            }
                            Spacer()
                            if viewModel.isSendingMediaCommand { ProgressView() }
                        }
                        .font(.title2)
                        .disabled(viewModel.isSendingMediaCommand)
                    }
                    if points.renderingControl != nil {
                        HStack {
                            Image(systemName: "speaker.fill")
                            Slider(value: $volume, in: 0...100, step: 1) { editing in
                                if !editing { viewModel.setVolume(Int(volume)) }
                            } label: {
                                Text("Громкость")
                            }
                            Image(systemName: "speaker.wave.3.fill")
                        }
                    }
                } else {
                    Text("Устройство не поддерживает управление медиа по UPnP")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Не удалось получить элементы управления")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            viewModel.loadUPnPControlsIfNeeded()
        }
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
