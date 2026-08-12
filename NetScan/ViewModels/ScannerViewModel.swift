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

        bonjourScanner.start { [weak self] name, ip in
            Task { @MainActor in
                self?.upsert(Device(id: ip, ipAddress: ip, bonjourName: name))
            }
        }

        let hosts = NetworkInfo.hostAddresses(in: local).filter { $0 != local.ip }
        totalHosts = hosts.count

        // The regular sweep only checks 5 ports, and routers often don't
        // answer any of them on 80/443 the way we probe — so it can end up
        // missing entirely. Give it its own wider, dedicated probe alongside
        // the main sweep instead of just hoping it turns up. There's no
        // public API for the real default-route IP, so we have a couple of
        // plausible gateway addresses (first-usable, last-usable) — tried
        // *in order*, one at a time, stopping at the first that answers.
        // Trying them all in parallel and labeling every responder "the
        // router" is how you end up with two routers in the list.
        let gatewayCandidates = NetworkInfo.gatewayGuesses(for: local).filter { $0 != local.ip }
        Task {
            for candidate in gatewayCandidates {
                if await self.probeGateway(ip: candidate) { break }
            }
        }

        Task {
            let localNetworkAccessLikelyBlocked = await subnetScanner.scan(
                hosts: hosts,
                onDeviceFound: { [weak self] device in
                    Task { @MainActor in
                        self?.upsert(device)
                        self?.resolveHostname(for: device.ipAddress)
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
                self.isScanning = false
                if localNetworkAccessLikelyBlocked {
                    // ENETDOWN on TCP probes — the documented signature of
                    // "Local Network" permission being denied or stuck (can
                    // persist even after re-enabling it in Settings until
                    // the device is restarted). An empty/thin result here
                    // means "can't see the network", not "nothing's there".
                    self.statusMessage = "Похоже, у приложения нет доступа к локальной сети. Проверь Настройки → Конфиденциальность и безопасность → Локальная сеть → NetScan. Если там уже включено, но не помогает — перезагрузи телефон."
                } else if self.devices.count <= 1 {
                    self.statusMessage = "Кроме этого устройства ничего не найдено"
                }
            }
        }
    }

    func stopScan() {
        bonjourScanner.stop()
        isScanning = false
    }

    /// Probes one gateway candidate. Returns whether it answered (alive or
    /// had an open port) — the caller stops trying further candidates as
    /// soon as one succeeds, so only one device ever ends up flagged as
    /// the router.
    @discardableResult
    private func probeGateway(ip: String) async -> Bool {
        let scanner = DeepPortScanner()
        async let result = scanner.scan(host: ip)
        async let alive = ICMPPinger.ping(host: ip, timeout: 1.0)

        let scanResult = await result
        let isAlive = await alive
        guard !scanResult.openPorts.isEmpty || isAlive else { return false }

        var device = Device(id: ip, ipAddress: ip, hostname: "Роутер",
                             isReachable: true, openPorts: scanResult.openPorts)
        device.portBanners = scanResult.banners
        device.isGateway = true
        upsert(device)
        resolveHostname(for: ip)
        return true
    }

    /// Reverse DNS is a separate, slower step (a few seconds worst case) on
    /// top of the initial liveness probe, so it runs fire-and-forget after a
    /// device is already shown — updating its name in place once/if it
    /// resolves, rather than delaying the device from appearing at all.
    private func resolveHostname(for ip: String) {
        Task {
            guard let name = await ReverseDNSResolver.resolve(ip: ip) else { return }
            upsert(Device(id: ip, ipAddress: ip, hostname: name))
        }
    }

    /// Merges rather than overwrites: a device can get upserted several
    /// times independently (initial sweep, gateway probe, reverse DNS,
    /// Bonjour resolution — each only knows a slice of the picture), and
    /// whichever lands later shouldn't erase what an earlier pass already
    /// found. Starting `merged` from the *existing* entry and only layering
    /// on genuinely new info from the incoming one (rather than the other
    /// way round) matters: an incoming partial update — e.g. reverse DNS
    /// only setting `hostname` — carries default/empty values for
    /// everything else, and starting from the incoming struct would silently
    /// reset `isReachable`, `responseTimeMs`, etc. back to their defaults.
    private func upsert(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            var merged = devices[index]
            merged.openPorts = Array(Set(merged.openPorts).union(device.openPorts)).sorted()
            merged.isGateway = merged.isGateway || device.isGateway
            merged.isReachable = merged.isReachable || device.isReachable
            merged.portBanners = merged.portBanners.merging(device.portBanners) { _, new in new }
            if let responseTimeMs = device.responseTimeMs { merged.responseTimeMs = responseTimeMs }
            if let hostname = device.hostname { merged.hostname = hostname }
            if let bonjourName = device.bonjourName { merged.bonjourName = bonjourName }
            devices[index] = merged
        } else {
            devices.append(device)
        }
        sortDevices()
    }

    /// Devices we could actually put a name to (hostname/Bonjour, including
    /// "Это устройство"/"Роутер") float to the top, alphabetically among
    /// themselves; anonymous IP-only entries stay below, sorted by address.
    private func sortDevices() {
        devices.sort { lhs, rhs in
            let lhsNamed = lhs.hostname != nil || lhs.bonjourName != nil
            let rhsNamed = rhs.hostname != nil || rhs.bonjourName != nil
            if lhsNamed != rhsNamed { return lhsNamed }
            if lhsNamed {
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.ipAddress.localizedStandardCompare(rhs.ipAddress) == .orderedAscending
        }
    }
}
