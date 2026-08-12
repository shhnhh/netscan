import SwiftUI

/// A logical star-topology map (router in the center, every discovered host
/// as a spoke around it) — this is what a home Wi-Fi network's shape
/// actually is, not a guess at where things physically sit in a room. Same
/// idea as Fing's "Network Map", which is topology, not geography.
struct NetworkMapView: View {
    let devices: [Device]

    private let ringRadius: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                    let point = position(for: index, total: devices.count, center: center)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point)
                    }
                    .stroke(lineColor(for: device), lineWidth: 1.5)
                }

                ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                    let point = position(for: index, total: devices.count, center: center)
                    NavigationLink(value: device) {
                        DeviceMapNode(device: device)
                    }
                    .buttonStyle(.plain)
                    .position(point)
                }

                RouterMapNode()
                    .position(center)
            }
        }
        .navigationTitle("Карта сети")
        .navigationDestination(for: Device.self) { device in
            DeviceDetailView(device: device)
        }
        .overlay(alignment: .bottom) {
            if devices.isEmpty {
                Text("Сначала запусти скан на вкладке устройств")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
        }
    }

    private func position(for index: Int, total: Int, center: CGPoint) -> CGPoint {
        guard total > 0 else { return center }
        let angle = (2 * .pi / CGFloat(total)) * CGFloat(index) - .pi / 2
        return CGPoint(
            x: center.x + ringRadius * cos(angle),
            y: center.y + ringRadius * sin(angle)
        )
    }

    private func lineColor(for device: Device) -> Color {
        if device.findings.contains(where: { $0.severity == .critical }) {
            return .red
        } else if device.findings.contains(where: { $0.severity == .warning }) {
            return .orange
        }
        return .green.opacity(0.5)
    }
}

private struct RouterMapNode: View {
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 56, height: 56)
                Image(systemName: "wifi.router.fill")
                    .foregroundStyle(.blue)
                    .font(.title2)
            }
            Text("Роутер")
                .font(.caption2)
        }
    }
}

private struct DeviceMapNode: View {
    let device: Device

    private var symbolName: String {
        if device.isCamera { return "video.fill" }
        if device.openPorts.contains(631) || device.openPorts.contains(9100) { return "printer.fill" }
        if device.openPorts.contains(62078) { return "iphone" }
        if device.openPorts.contains(7000) { return "airplayaudio" }
        return "network"
    }

    private var tint: Color {
        if device.findings.contains(where: { $0.severity == .critical }) { return .red }
        if device.findings.contains(where: { $0.severity == .warning }) { return .orange }
        return .green
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
            }
            Text(device.displayName)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: 70)
        }
    }
}

#Preview {
    NavigationStack {
        NetworkMapView(devices: [
            Device(id: "192.168.1.10", ipAddress: "192.168.1.10", openPorts: [80]),
            Device(id: "192.168.1.20", ipAddress: "192.168.1.20", openPorts: [554]),
            Device(id: "192.168.1.30", ipAddress: "192.168.1.30", openPorts: [9100]),
        ])
    }
}
