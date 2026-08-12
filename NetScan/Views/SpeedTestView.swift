import SwiftUI

struct SpeedTestView: View {
    @StateObject private var viewModel = SpeedTestViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                metricRow(title: "Пинг", value: viewModel.pingMs.map { "\(Int($0)) ms" }, active: viewModel.phase == .ping)
                Divider()
                metricRow(title: "Скачивание", value: viewModel.downloadMbps.map { String(format: "%.1f Мбит/с", $0) }, active: viewModel.phase == .download)
                Divider()
                metricRow(title: "Отдача", value: viewModel.uploadMbps.map { String(format: "%.1f Мбит/с", $0) }, active: viewModel.phase == .upload)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Button {
                viewModel.start()
            } label: {
                Group {
                    if viewModel.isRunning {
                        ProgressView()
                    } else {
                        Text(viewModel.phase == .done ? "Повторить" : "Начать тест")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRunning)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("Тест скорости")
    }

    private func metricRow(title: String, value: String?, active: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if active && value == nil {
                ProgressView()
            } else {
                Text(value ?? "—")
                    .foregroundStyle(.secondary)
                    .fontWeight(.semibold)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SpeedTestView()
    }
}
