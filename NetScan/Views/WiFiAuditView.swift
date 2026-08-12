import SwiftUI

struct WiFiAuditView: View {
    @State private var network: WiFiSecurityInfo.CurrentNetwork?
    @State private var isEvilTwinSuspected = false
    @State private var isLoading = true
    @State private var notAvailable = false

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
            } else if notAvailable {
                Section {
                    Text("Не удалось получить данные о сети. Убедись, что подключён к Wi-Fi.")
                        .foregroundStyle(.secondary)
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
        notAvailable = current == nil
        if let current {
            isEvilTwinSuspected = WiFiHistoryStore.checkAndRecord(ssid: current.ssid, bssid: current.bssid)
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        WiFiAuditView()
    }
}
