import Foundation

@MainActor
final class DeviceDetailViewModel: ObservableObject {
    @Published private(set) var device: Device
    @Published private(set) var isDeepScanning = false

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
}
