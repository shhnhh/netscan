import Foundation

@MainActor
final class DeviceDetailViewModel: ObservableObject {
    @Published private(set) var device: Device
    @Published private(set) var isDeepScanning = false
    @Published private(set) var isPinging = false
    @Published private(set) var lastPingMs: Double?

    private let scanner = DeepPortScanner()

    init(device: Device) {
        self.device = device
    }

    func runDeepScan() {
        guard !isDeepScanning else { return }
        isDeepScanning = true

        Task {
            let result = await scanner.scan(host: device.ipAddress)
            let analysis = SecurityAnalyzer.analyze(openPorts: result.openPorts, banners: result.banners)

            device.openPorts = Array(Set(device.openPorts).union(result.openPorts)).sorted()
            device.portBanners = result.banners
            device.findings = analysis.findings
            device.isCamera = analysis.isCamera
            device.cameraVendor = analysis.cameraVendor
            device.isDeepScanned = true
            isDeepScanning = false
        }
    }

    func runPing() {
        guard !isPinging else { return }
        isPinging = true
        lastPingMs = nil

        Task {
            let start = Date()
            let alive = await ICMPPinger.ping(host: device.ipAddress, timeout: 1.5)
            lastPingMs = alive ? Date().timeIntervalSince(start) * 1000 : nil
            isPinging = false
        }
    }
}
