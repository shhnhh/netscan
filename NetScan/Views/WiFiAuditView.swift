import SwiftUI

struct WiFiAuditView: View {
    @State private var network: WiFiSecurityInfo.CurrentNetwork?
    @State private var isEvilTwinSuspected = false
    @State private var isLoading = true
    @State private var failureReason: FailureReason?

    private enum FailureReason {
        case noWiFi
        case permissionDenied
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Проверяю сеть…")
                    }
                }
            } else if let network {
                Section("Текущая сеть") {
                    LabeledContent("SSID", value: network.ssid)
                    LabeledContent("BSSID (точка доступа)", value: network.bssid)
                }

                Section("Оценка") {
                    if !network.isSecure {
                        Label("Сеть открыта, без пароля", systemImage: "lock.open.fill")
                            .foregroundStyle(.red)
                        Text("Весь незашифрованный трафик в этой сети виден любому рядом. Не вводи пароли и не заходи в банк-приложения на такой сети.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Сеть защищена паролем", systemImage: "lock.fill")
                            .foregroundStyle(.green)
                        Text("iOS не даёт приложениям узнать точный тип шифрования (WPA2/WPA3) — только сам факт, что сеть закрыта.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if isEvilTwinSuspected {
                        Label("Подозрение на подменную точку доступа", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Эта сеть раньше была на другом оборудовании (другой BSSID). Это может быть поддельная точка с тем же именем — так делают для перехвата трафика. Если ты не менял роутер — будь осторожен.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let failureReason {
                Section {
                    switch failureReason {
                    case .noWiFi:
                        Text("Не подключён к Wi-Fi.")
                            .foregroundStyle(.secondary)
                    case .permissionDenied:
                        Label("iOS не отдаёт данные о сети этому приложению", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Wi-Fi подключён, но система не даёт приложению данные о сети — скорее всего разрешение \"Access WiFi Information\" не подхватилось при переподписи через iLoader. Это известное ограничение сборки без Mac и платного аккаунта разработчика.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Wi-Fi аудит")
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        let current = await WiFiSecurityInfo.fetchCurrent()
        network = current
        if let current {
            failureReason = nil
            isEvilTwinSuspected = WiFiHistoryStore.checkAndRecord(ssid: current.ssid, bssid: current.bssid)
        } else {
            // NEHotspotNetwork returned nothing — could genuinely mean "not on
            // Wi-Fi", or could mean iOS is withholding the data from this app
            // (missing entitlement). NetworkInfo.currentWiFiAddress() reads the
            // en0 interface IP directly via getifaddrs, which needs no special
            // entitlement and is known to work — use it as ground truth to
            // tell the two cases apart instead of always blaming "not connected".
            failureReason = NetworkInfo.currentWiFiAddress() == nil ? .noWiFi : .permissionDenied
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        WiFiAuditView()
    }
}
