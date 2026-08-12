import SwiftUI

struct WiFiAuditView: View {
    @State private var network: WiFiSecurityInfo.CurrentNetwork?
    @State private var isEvilTwinSuspected = false
    @State private var isLoading = true
    @State private var failureReason: FailureReason?

    private enum FailureReason {
        case noWiFi
        case locationPermissionDenied
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
                } footer: {
                    Text("При первом запуске iOS спросит разрешение на геолокацию — это нужно только технически, чтобы получить название сети, сама позиция не используется. Если системный запрос не появляется, проверка завершится сама максимум через минуту.")
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
                    case .locationPermissionDenied:
                        Label("Нужен доступ к геолокации", systemImage: "location.slash.fill")
                            .foregroundStyle(.orange)
                        Text("iOS отдаёт данные о Wi-Fi-сети приложению только если у него есть разрешение на геолокацию \"При использовании\" — так Apple ограничивает доступ к SSID/BSSID. Разреши доступ в Настройки → Конфиденциальность → Геолокация → NetScan и попробуй ещё раз. Сама геопозиция приложению не нужна и никуда не отправляется — это чисто техническое требование API.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .permissionDenied:
                        Label("iOS не отдаёт данные о сети этому приложению", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Разрешение на геолокацию есть, Wi-Fi подключён, но данные о сети всё равно недоступны — скорее всего entitlement \"Access WiFi Information\" не подхватился при переподписи через iLoader. Это известное ограничение сборки без Mac и платного аккаунта разработчика.")
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
        network = nil

        // NetworkInfo.currentWiFiAddress() reads the en0 interface IP
        // directly via getifaddrs — needs no special entitlement/permission
        // and is known to work — so it's ground truth for "genuinely not on
        // Wi-Fi" vs. "iOS is withholding the data from this app".
        guard NetworkInfo.currentWiFiAddress() != nil else {
            failureReason = .noWiFi
            isLoading = false
            return
        }

        switch await WiFiSecurityInfo.fetchCurrent() {
        case .success(let current):
            network = current
            failureReason = nil
            isEvilTwinSuspected = WiFiHistoryStore.checkAndRecord(ssid: current.ssid, bssid: current.bssid)
        case .locationPermissionDenied:
            failureReason = .locationPermissionDenied
        case .unavailable:
            failureReason = .permissionDenied
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        WiFiAuditView()
    }
}
