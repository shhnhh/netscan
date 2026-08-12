import SwiftUI

struct AddCameraView: View {
    @ObservedObject var store: CameraStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var urlString = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Камера") {
                    TextField("Название", text: $name)
                    TextField("MJPEG URL (http://ip/...)", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Авторизация (если нужна)") {
                    TextField("Логин", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Пароль", text: $password)
                }
                Section {
                    Text("Нужна ссылка именно на MJPEG-поток (обычно вида http://IP/mjpg/video.mjpg, http://IP/video.cgi и похожие — смотри в настройках/документации своей камеры). Чистый rtsp:// сейчас не поддерживается — iOS не умеет проигрывать его без стороннего плеера.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Добавить камеру")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let camera = SavedCamera(
                            name: name.isEmpty ? urlString : name,
                            streamURLString: urlString,
                            username: username.isEmpty ? nil : username
                        )
                        store.add(camera, password: password.isEmpty ? nil : password)
                        dismiss()
                    }
                    .disabled(urlString.isEmpty)
                }
            }
        }
    }
}

#Preview {
    AddCameraView(store: CameraStore())
}
