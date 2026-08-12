import SwiftUI

struct DeviceRow: View {
    let device: Device

    private var hasCriticalFinding: Bool {
        device.findings.contains { $0.severity == .critical }
    }

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
            if device.isCamera {
                Image(systemName: "video.fill")
                    .foregroundStyle(.orange)
            }
            if hasCriticalFinding {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            if let ms = device.responseTimeMs {
                Text("\(Int(ms)) ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
