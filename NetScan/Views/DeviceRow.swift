import SwiftUI

struct DeviceRow: View {
    let device: Device

    private var hasCriticalFinding: Bool {
        device.findings.contains { $0.severity == .critical }
    }

    private var platform: DevicePlatform {
        PlatformGuesser.guess(for: device)
    }

    private var leadingSymbol: String {
        if device.isGateway { return "wifi.router.fill" }
        return platform.symbolName
    }

    private var leadingTint: Color {
        device.isGateway ? .blue : .green
    }

    private var subtitle: String {
        var parts = [device.ipAddress]
        if device.isGateway {
            parts.append("роутер")
        } else if platform != .unknown {
            parts.append(platform.label)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack {
            Image(systemName: leadingSymbol)
                .foregroundStyle(leadingTint)
                .frame(width: 22)
            VStack(alignment: .leading) {
                Text(device.displayName)
                    .font(.body)
                Text(subtitle)
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
