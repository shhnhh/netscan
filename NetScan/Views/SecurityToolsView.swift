import SwiftUI

struct SecurityToolsView: View {
    var body: some View {
        List {
            NavigationLink {
                PasswordCheckView()
            } label: {
                Label("Проверка пароля на утечки", systemImage: "key.fill")
            }

            NavigationLink {
                WiFiAuditView()
            } label: {
                Label("Wi-Fi аудит текущей сети", systemImage: "wifi.exclamationmark")
            }
        }
        .navigationTitle("Безопасность")
    }
}

#Preview {
    NavigationStack {
        SecurityToolsView()
    }
}
