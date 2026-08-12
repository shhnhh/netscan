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
        // Show the vendor here only when it isn't already the display name
        // (when there's no hostname/Bonjour name, the vendor is the title).
        if let vendor = device.macVendor, vendor != device.displayName {
            parts.append(vendor)
        }
        let count = device.openPorts.count
        if count > 0 {
            parts.append("\(count) \(Self.portWord(count))")
        }
        return parts.joined(separator: " · ")
    }

    private static func portWord(_ n: Int) -> String {
        let mod100 = n % 100
        let mod10 = n % 10
        if (11...14).contains(mod100) { return "портов" }
        if mod10 == 1 { return "порт" }
        if (2...4).contains(mod10) { return "порта" }
        return "портов"
    }

    var body: some View {
        HStack {
            Image(systemName: leadingSymbol)
                .foregroundStyle(leadingTint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.body)
                    if device.isNewDevice {
                        Text("NEW")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
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
