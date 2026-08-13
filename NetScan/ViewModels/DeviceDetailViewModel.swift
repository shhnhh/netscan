import Foundation

@MainActor
final class DeviceDetailViewModel: ObservableObject {
    @Published private(set) var device: Device
    @Published private(set) var isDeepScanning = false
    @Published private(set) var isPinging = false
    @Published private(set) var lastPingMs: Double?

    @Published private(set) var isWaking = false
    @Published private(set) var wakeResultMessage: String?

    @Published private(set) var upnpControlPoints: UPnPMediaController.ControlPoints?
    @Published private(set) var isLoadingUPnP = false
    @Published private(set) var isSendingMediaCommand = false

    @Published private(set) var isPrintingTestPage = false
    @Published private(set) var printResultMessage: String?

    private let scanner = DeepPortScanner()

    init(device: Device) {
        self.device = device
    }

    /// The best URL to open the device's own web UI in — prefers HTTPS when
    /// it's open (avoids a plaintext-login warning for devices that support
    /// both), otherwise falls back to plain HTTP on whichever of the common
    /// ports actually answered during the scan.
    var webUIURL: URL? {
        let ports = Set(device.openPorts)
        if ports.contains(443) { return URL(string: "https://\(device.ipAddress)") }
        if ports.contains(8443) { return URL(string: "https://\(device.ipAddress):8443") }
        if ports.contains(80) { return URL(string: "http://\(device.ipAddress)") }
        if ports.contains(8080) { return URL(string: "http://\(device.ipAddress):8080") }
        return nil
    }

    var canWake: Bool { device.macAddress != nil }
    var canPrintTestPage: Bool { device.openPorts.contains(9100) }
    var canControlMedia: Bool { device.ssdpLocation != nil }

    func wakeOnLAN() {
        guard let mac = device.macAddress, !isWaking else { return }
        isWaking = true
        wakeResultMessage = nil

        Task {
            do {
                try WakeOnLAN.wake(mac: mac)
                wakeResultMessage = "Magic packet отправлен"
            } catch {
                wakeResultMessage = "Не удалось отправить пакет"
            }
            isWaking = false
        }
    }

    func loadUPnPControlsIfNeeded() {
        guard let location = device.ssdpLocation, upnpControlPoints == nil, !isLoadingUPnP else { return }
        isLoadingUPnP = true

        Task {
            let points = await UPnPMediaController.discoverControlPoints(location: location)
            upnpControlPoints = points
            isLoadingUPnP = false
        }
    }

    func sendMediaAction(_ action: UPnPMediaController.TransportAction) {
        guard let controlURL = upnpControlPoints?.avTransport, !isSendingMediaCommand else { return }
        isSendingMediaCommand = true

        Task {
            switch action {
            case .play: await UPnPMediaController.play(controlURL: controlURL)
            case .pause: await UPnPMediaController.pause(controlURL: controlURL)
            case .stop: await UPnPMediaController.stop(controlURL: controlURL)
            }
            isSendingMediaCommand = false
        }
    }

    func setVolume(_ volume: Int) {
        guard let controlURL = upnpControlPoints?.renderingControl else { return }
        Task {
            await UPnPMediaController.setVolume(volume, controlURL: controlURL)
        }
    }

    func printTestPage() {
        guard !isPrintingTestPage else { return }
        isPrintingTestPage = true
        printResultMessage = nil

        Task {
            let success = await RawPrinter.printTestPage(host: device.ipAddress, deviceName: device.displayName)
            printResultMessage = success ? "Отправлено на печать" : "Не удалось отправить задание"
            isPrintingTestPage = false
        }
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
