import SwiftUI

struct PasswordCheckView: View {
    @State private var password = ""
    @State private var isChecking = false
    @State private var result: PasswordBreachChecker.Result?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                SecureField("Пароль", text: $password)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                Button {
                    check()
                } label: {
                    HStack {
                        if isChecking {
                            ProgressView()
                        } else {
                            Text("Проверить")
                        }
                    }
                }
                .disabled(password.isEmpty || isChecking)
            } footer: {
                Text("Пароль никуда не отправляется целиком: на сервер уходят только первые 5 символов его SHA-1 хеша (k-anonymity), по ним нельзя восстановить пароль. Проверка через открытую базу Pwned Passwords (Have I Been Pwned).")
            }

            if let result {
                Section("Результат") {
                    if result.isBreached {
                        Label("Найден в утечках: \(result.timesSeen) раз", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text("Этот пароль встречался в утёкших базах данных. Лучше его сменить — особенно если используешь его ещё где-то.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Не найден в известных утечках", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Проверка пароля")
    }

    private func check() {
        isChecking = true
        errorMessage = nil
        result = nil
        let pw = password

        Task {
            do {
                let r = try await PasswordBreachChecker.check(password: pw)
                result = r
            } catch {
                errorMessage = "Не удалось проверить — проверь интернет-соединение."
            }
            isChecking = false
        }
    }
}

#Preview {
    NavigationStack {
        PasswordCheckView()
    }
}
