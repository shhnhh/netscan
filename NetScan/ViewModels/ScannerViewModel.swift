import Foundation
import SwiftUI

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published private(set) var devices: [Device] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedCount = 0
    @Published private(set) var totalHosts = 0
    @Published var statusMessage: String?

    private let subnetScanner = SubnetScanner()
    private let bonjourScanner = BonjourScanner()

    func startScan() {
        guard !isScanning else { return }

        guard let local = NetworkInfo.currentWiFiAddress() else {
            statusMessage = "Подключись к Wi-Fi, чтобы просканировать сеть"
            return
        }

        isScanning = true
        statusMessage = nil
        devices.removeAll()
        scannedCount = 0

        // Always show this device — it doesn't need probing, we already
        // know it's alive, it's the one running the scan.
        upsert(Device(id: local.ip, ipAddress: local.ip, hostname: "Это устройство", isReachable: true))

        bonjourScanner.start { [weak self] name, _ in
            Task { @MainActor in
                self?.mergeBonjourName(name)
            }
        }

        let hosts = NetworkInfo.hostAddresses(in: local).filter { $0 != local.ip }
        totalHosts = hosts.count

        // The regular sweep only checks 5 ports, and routers often don't
        // answer any of them on 80/443 the way we probe — so it can end up
        // missing entirely. Give it its own wider, dedicated probe alongside
        // the main sweep instead of just hoping it turns up.
        if let gatewayIP = NetworkInfo.gatewayGuess(for: local), gatewayIP != local.ip {
            Task {
                await self.probeGateway(ip: gatewayIP)
            }
        }

        Task {
            await subnetScanner.scan(
                hosts: hosts,
                onDeviceFound: { [weak self] device in
                    Task { @MainActor in
                        self?.upsert(device)
                    }
                },
                onProgress: { [weak self] completed, total in
                    Task { @MainActor in
                        self?.scannedCount = completed
                        self?.totalHosts = total
                    }
                }
            )
            await MainActor.run {
                self.attachMacAddresses()
                self.isScanning = false
                if self.devices.count <= 1 {
                    self.statusMessage = "Кроме этого устройства ничего не найдено"
                }
            }
        }
    }

    func stopScan() {
        bonjourScanner.stop()
        isScanning = false
    }

    private func probeGateway(ip: String) async {
        let scanner = DeepPortScanner()
        async let result = scanner.scan(host: ip)
        async let alive = ICMPPinger.ping(host: ip, timeout: 1.0)

        let scanResult = await result
        guard !scanResult.openPorts.isEmpty || (await alive) else { return }

        var device = Device(id: ip, ipAddress: ip, hostname: "Роутер (предположительно)",
                             isReachable: true, openPorts: scanResult.openPorts)
        device.portBanners = scanResult.banners
        device.isGateway = true
        upsert(device)
    }

    private func attachMacAddresses() {
        let arpTable = ARPTableReader.currentEntries()
        guard !arpTable.isEmpty else { return }
        for index in devices.indices {
            if let mac = arpTable[devices[index].ipAddress] {
                devices[index].macAddress = mac
            }
        }
    }

    /// Merges rather than overwrites: the gateway gets probed twice (its own
    /// dedicated wider probe, plus the regular sweep since it's a normal
    /// host too), and whichever result lands second shouldn't erase the
    /// richer one.
    private func upsert(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            var merged = device
            merged.openPorts = Array(Set(devices[index].openPorts).union(device.openPorts)).sorted()
            merged.isGateway = devices[index].isGateway || device.isGateway
            merged.portBanners = devices[index].portBanners.merging(device.portBanners) { _, new in new }
            if device.hostname == nil { merged.hostname = devices[index].hostname }
            if device.macAddress == nil { merged.macAddress = devices[index].macAddress }
            devices[index] = merged
        } else {
            devices.append(device)
            devices.sort { $0.ipAddress.localizedStandardCompare($1.ipAddress) == .orderedAscending }
        }
    }

    /// Bonjour results don't carry the resolved IP directly in the summary handler;
    /// this is a placeholder for name correlation, refined once we resolve endpoints.
    private func mergeBonjourName(_ name: String) {
        // Intentionally left minimal for the MVP — full IP correlation requires
        // resolving each NWBrowser.Result.endpoint via NWConnection, added next.
    }
}
