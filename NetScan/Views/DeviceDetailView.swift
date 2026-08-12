import SwiftUI

struct DeviceDetailView: View {
    let device: Device

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
            }

            Section("Открытые порты") {
                if device.openPorts.isEmpty {
                    Text("Не обнаружены")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(device.openPorts, id: \.self) { port in
                        HStack {
                            Text("\(port)")
                            Spacer()
                            if let known = WellKnownPort(rawValue: port) {
                                Text(known.label)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(device.displayName)
    }
}
