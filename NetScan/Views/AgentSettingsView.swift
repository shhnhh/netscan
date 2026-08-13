import SwiftUI

/// Lets the user point the app at an optional companion `netscan-agent.py`
/// (see /agent in the repo) running on some other always-on machine on the
/// LAN — the only way to get real MAC addresses on iOS versions where the
/// OS masks them even for the ARP-cache read (see README for the whole
/// story). Purely optional: the app works exactly as before if this is
/// left off.
struct AgentSettingsView: View {
    @AppStorage(AgentSettings.enabledKey) private var isEnabled = false
    @AppStorage(AgentSettings.hostKey) private var host = ""
    @AppStorage(AgentSettings.tokenKey) private var token = ""

    var body: some View {
        Form {
            Section {
                Toggle("Использовать LAN-агент", isOn: $isEnabled)
            } footer: {
                Text("Небольшой скрипт (netscan-agent.py в репозитории проекта), который запускаешь на любом всегда включённом устройстве в своей сети — читает настоящую ARP-таблицу ОС (без песочницы iOS) и отдаёт реальные MAC-адреса вместо заглушки 02:00:00:00:00:00. Тот же принцип, что у Fing Desktop/Fingbox, просто в виде одного файла.")
            }

            if isEnabled {
                Section("Адрес агента") {
                    TextField("192.168.1.50:8756", text: $host)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Токен (если задавали при запуске)", text: $token)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            Section("Как запустить агент") {
                Text("На компьютере/Raspberry Pi/NAS в этой же сети:\npython3 netscan-agent.py --token СЕКРЕТ\n\nСкрипт без зависимостей, только стандартная библиотека Python 3. Работает на Linux и macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("LAN-агент")
    }
}

#Preview {
    NavigationStack {
        AgentSettingsView()
    }
}
