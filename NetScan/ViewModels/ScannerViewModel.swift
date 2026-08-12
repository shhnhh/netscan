import Foundation
import SwiftUI

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published private(set) var devices: [Device] = []
    @Published private(set) var isScanning = false
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

        bonjourScanner.start { [weak self] name, _ in
            Task { @MainActor in
                self?.mergeBonjourName(name)
            }
        }

        let hosts = NetworkInfo.hostAddresses(in: local)
        Task {
            await subnetScanner.scan(hosts: hosts) { [weak self] device in
                Task { @MainActor in
                    self?.upsert(device)
                }
            }
            await MainActor.run {
                self.isScanning = false
                if self.devices.isEmpty {
                    self.statusMessage = "Устройств не найдено"
                }
            }
        }
    }

    func stopScan() {
        bonjourScanner.stop()
        isScanning = false
    }

    private func upsert(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
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
