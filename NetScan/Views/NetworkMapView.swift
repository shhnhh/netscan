import SwiftUI

/// A logical star-topology map (router in the center, every discovered host
/// as a spoke around it) — this is what a home Wi-Fi network's shape
/// actually is, not a guess at where things physically sit in a room. Same
/// idea as Fing's "Network Map", which is topology, not geography.
///
/// Device taps push through the *parent* NavigationStack's
/// `navigationDestination(for: Device.self)` — this view deliberately does
/// not register its own, since two handlers for the same type on one stack
/// is what caused taps here to resolve to the wrong destination before.
struct NetworkMapView: View {
    let devices: [Device]

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    /// Devices arranged in concentric rings instead of one single circle —
    /// with hundreds of devices, one ring makes the radius (and therefore
    /// the distance from the router to *every* node) huge, so opening the
    /// map centered on the router shows nothing but the router. Rings keep
    /// the first couple dozen devices close by, and the rest reachable by
    /// panning/zooming outward.
    private let devicesPerRing = 14
    private let baseRadius: CGFloat = 130
    private let ringSpacing: CGFloat = 100

    private var ringCount: Int {
        devices.isEmpty ? 0 : (devices.count - 1) / devicesPerRing + 1
    }

    private var canvasRadius: CGFloat {
        baseRadius + CGFloat(max(ringCount - 1, 0)) * ringSpacing + 70
    }

    private var canvasSize: CGFloat { canvasRadius * 2 }

    private var showLabels: Bool {
        scale > 0.9
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: canvasSize / 2, y: canvasSize / 2)

            ZStack {
                ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                    let point = position(for: index, center: center)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point)
                    }
                    .stroke(lineColor(for: device), lineWidth: 1.5)
                }

                ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                    let point = position(for: index, center: center)
                    NavigationLink(value: device) {
                        DeviceMapNode(device: device, showLabel: showLabels)
                    }
                    .buttonStyle(.plain)
                    .position(point)
                }

                RouterMapNode()
                    .position(center)
            }
            .frame(width: canvasSize, height: canvasSize)
            .scaleEffect(scale)
            .offset(offset)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newScale = min(max(scale * value, 0.1), 5)
                            // Keep whatever's currently at screen-center under
                            // screen-center as scale changes, instead of the
                            // zoom snapping back toward the canvas's own
                            // center (the router) every time you pinch after
                            // panning away from it.
                            let ratio = newScale / scale
                            offset = CGSize(width: offset.width * ratio, height: offset.height * ratio)
                            scale = newScale
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        },
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in lastOffset = offset }
                )
            )
            .clipped()
        }
        .navigationTitle("Карта сети (\(devices.count))")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Центр") {
                    withAnimation {
                        scale = 1
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
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

    private func position(for index: Int, center: CGPoint) -> CGPoint {
        let ring = index / devicesPerRing
        let ringStart = ring * devicesPerRing
        let countInRing = min(devicesPerRing, devices.count - ringStart)
        let slot = index - ringStart

        // Stagger alternating rings by half a step so nodes don't line up
        // radially into spokes-within-spokes.
        let staggerOffset: CGFloat = ring.isMultiple(of: 2) ? 0 : (.pi / CGFloat(max(countInRing, 1)))
        let angle = (2 * .pi / CGFloat(max(countInRing, 1))) * CGFloat(slot) - .pi / 2 + staggerOffset
        let radius = baseRadius + CGFloat(ring) * ringSpacing

        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
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
    let showLabel: Bool

    private var symbolName: String {
        if device.isGateway { return "wifi.router.fill" }
        if device.isCamera { return "video.fill" }
        if device.openPorts.contains(631) || device.openPorts.contains(9100) { return "printer.fill" }
        if device.openPorts.contains(7000) { return "airplayaudio" }
        let platform = PlatformGuesser.guess(for: device)
        return platform == .unknown ? "network" : platform.symbolName
    }

    private var tint: Color {
        if device.findings.contains(where: { $0.severity == .critical }) { return .red }
        if device.findings.contains(where: { $0.severity == .warning }) { return .orange }
        if device.isGateway { return .blue }
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
            if showLabel {
                Text(device.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 70)
            }
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
        .navigationDestination(for: Device.self) { device in
            DeviceDetailView(device: device)
        }
    }
}
