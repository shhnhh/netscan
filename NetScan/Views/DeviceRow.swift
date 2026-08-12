import SwiftUI

struct DeviceRow: View {
    let device: Device

    var body: some View {
        HStack {
            Image(systemName: "network")
                .foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text(device.displayName)
                    .font(.body)
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let ms = device.responseTimeMs {
                Text("\(Int(ms)) ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
