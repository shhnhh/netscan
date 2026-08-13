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

    /// Identifies the network for the new-device history — the gateway
    /// address, stable across DHCP lease churn within one network.
    private var currentNetworkKey = ""

    /// IPs already queried via LockdownClient this scan — avoids re-querying
    /// the same iOS device every time a later probe (gateway check, ARP
    /// pass) re-upserts it with the 62078 port still in its open-port set.
    private var queriedLockdownIPs: Set<String> = []

    /// Same dedupe idea as `queriedLockdownIPs`, for NetBIOS (139/445) hosts.
    private var queriedNetBIOSIPs: Set<String> = []

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
        queriedLockdownIPs.removeAll()
        queriedNetBIOSIPs.removeAll()

        // Always show this device — it doesn't need probing, we already
        // know it's alive, it's the one running the scan.
        upsert(Device(id: local.ip, ipAddress: local.ip, hostname: "Это устройство", isReachable: true))

        bonjourScanner.start { [weak self] name, ip in
            Task { @MainActor in
                self?.upsert(Device(id: ip, ipAddress: ip, bonjourName: name))
            }
        }

        // Second, independent source of self-announced device names: SSDP
        // catches smart TVs, routers, speakers and IoT gear that don't speak
        // any of the Bonjour service types above but do answer UPnP
        // discovery — often with the same name the device uses everywhere,
        // including Bluetooth pairing.
        Task {
            let ssdpResults = await SSDPScanner.discover()
            await MainActor.run {
                for result in ssdpResults {
                    self.upsert(Device(id: result.ip, ipAddress: result.ip, bonjourName: result.name))
                }
            }
        }

        let hosts = NetworkInfo.hostAddresses(in: local).filter { $0 != local.ip }
        totalHosts = hosts.count

        // The regular sweep only checks 5 ports, and routers often don't
        // answer any of them on 80/443 the way we probe — so it can end up
        // missing entirely. Give it its own wider, dedicated probe alongside
        // the main sweep instead of just hoping it turns up. Prefer the real
        // default route read from the kernel's routing table — correct even
        // when the router doesn't sit at the subnet's first/last address
        // (e.g. carrier/CGNAT-style networks) — and fall back to guessing
        // first-usable/last-usable only if that lookup comes back empty.
        // Candidates are tried *in order*, one at a time, stopping at the
        // first that answers: trying them all in parallel and labeling every
        // responder "the router" is how you end up with two routers shown.
        Task {
            let realGateway = await ARPResolver.defaultGateway()
            var candidates = NetworkInfo.gatewayGuesses(for: local)
            if let realGateway {
                candidates.removeAll { $0 == realGateway }
                candidates.insert(realGateway, at: 0)
            }
            let gatewayCandidates = candidates.filter { $0 != local.ip }
            await MainActor.run { self.currentNetworkKey = gatewayCandidates.first ?? local.ip }
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
                        if device.openPorts.contains(WellKnownPort.lockdown.rawValue) {
                            self?.resolveLockdownName(for: device.ipAddress)
                        }
                        if device.openPorts.contains(WellKnownPort.netbios.rawValue) || device.openPorts.contains(WellKnownPort.smb.rawValue) {
                            self?.resolveNetBIOSName(for: device.ipAddress)
                        }
                    }
                },
                onProgress: { [weak self] completed, total in
                    Task { @MainActor in
                        self?.scannedCount = completed
                        self?.totalHosts = total
                    }
                }
            )
            // The ARP cache is populated as a side effect of the probing we
            // just did (ping/TCP forces the kernel to resolve each host's
            // MAC), so read it once the sweep is done and fold the addresses
            // into the devices. Run it a second time shortly after: some
            // entries land in the cache slightly after their probe completes.
            await self.applyARPTable()

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

            // Second pass: a MAC often lands in the ARP cache a beat after
            // its host answered, so a delayed re-read picks up the stragglers
            // the first pass missed.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self.applyARPTable()

            // Once MACs are as complete as they'll get, compare against the
            // network's history to flag new arrivals and update the baseline.
            self.markNewDevices()
            self.applyQuickSecurity()
        }
    }

    /// Number of devices with at least a warning-level issue — drives the
    /// summary line on the device list.
    var devicesWithIssues: Int {
        devices.filter { device in
            device.findings.contains { $0.severity >= .warning }
        }.count
    }

    /// Plain-text scan report for sharing/export via ShareLink.
    var reportText: String {
        var lines = ["NetScan — отчёт о сканировании сети"]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        lines.append("Дата: \(formatter.string(from: Date()))")
        lines.append("Устройств найдено: \(devices.count)")
        if devicesWithIssues > 0 {
            lines.append("С потенциальными проблемами: \(devicesWithIssues)")
        }
        lines.append("")

        for device in devices {
            lines.append("• \(device.displayName) (\(device.ipAddress))")
            if let mac = device.macAddress {
                lines.append("  MAC: \(mac)" + (device.macVendor.map { " (\($0))" } ?? ""))
            }
            if device.isNewDevice {
                lines.append("  [новое устройство в сети]")
            }
            if !device.openPorts.isEmpty {
                lines.append("  Порты: \(device.openPorts.map(String.init).joined(separator: ", "))")
            }
            for finding in device.findings {
                lines.append("  [\(finding.severity.label)] \(finding.title)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Runs the port-based security heuristics on every device right after the
    /// sweep, so risky hosts light up in the list without the user opening
    /// each one. Skips devices already deep-scanned (their findings include
    /// banner analysis, which is richer than what the sweep's ports alone
    /// give) so this never downgrades a manual deep scan.
    private func applyQuickSecurity() {
        for index in devices.indices where !devices[index].isDeepScanned {
            let analysis = SecurityAnalyzer.analyze(
                openPorts: devices[index].openPorts,
                banners: devices[index].portBanners)
            devices[index].findings = analysis.findings
            if analysis.isCamera { devices[index].isCamera = true }
            if devices[index].cameraVendor == nil {
                devices[index].cameraVendor = analysis.cameraVendor
            }
        }
    }

    /// Flags devices whose MAC wasn't seen on this network before, then folds
    /// this scan's MACs into the network's baseline for next time. The very
    /// first scan of a network establishes the baseline without flagging
    /// anything (everything would trivially be "new" otherwise).
    private func markNewDevices() {
        let network = currentNetworkKey
        guard !network.isEmpty else { return }

        let macs = Set(devices.compactMap { $0.macAddress })
        if NetworkHistoryStore.hasBaseline(network: network) {
            let known = NetworkHistoryStore.seenMacs(network: network)
            for index in devices.indices {
                if let mac = devices[index].macAddress, !known.contains(mac) {
                    devices[index].isNewDevice = true
                }
            }
        }
        NetworkHistoryStore.record(macs: macs, network: network)
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

    /// Reads the kernel ARP cache and folds each MAC (plus its guessed
    /// vendor) into the matching device already in the list. Only annotates
    /// devices we already found some other way — it does not add hosts, since
    /// the cache can hold stale entries for addresses no longer present.
    private func applyARPTable() async {
        let snapshot = await ARPResolver.snapshot()
        guard !snapshot.isEmpty else { return }
        var changed = false
        for (ip, entry) in snapshot {
            guard let index = devices.firstIndex(where: { $0.id == ip }) else { continue }
            if devices[index].macAddress != entry.mac {
                devices[index].macAddress = entry.mac
                devices[index].macVendor = entry.vendor
                changed = true
            }
        }
        // A newly-attached vendor can turn an anonymous IP into a "named"
        // device, which changes where it belongs in the ordering.
        if changed { sortDevices() }
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

    /// An open 62078 is iOS's lockdown/Wi-Fi-sync service — the actual
    /// device name (e.g. "Fedor's iPhone") is one unauthenticated query away
    /// via LockdownClient, no ARP/Bonjour/SSDP guesswork needed for these.
    private func resolveLockdownName(for ip: String) {
        guard !queriedLockdownIPs.contains(ip) else { return }
        queriedLockdownIPs.insert(ip)
        Task {
            guard let name = await LockdownClient.deviceName(host: ip) else { return }
            upsert(Device(id: ip, ipAddress: ip, hostname: name))
        }
    }

    /// An open 139/445 (NetBIOS/SMB) is a strong signal of a Windows host —
    /// these don't run Bonjour/SSDP/lockdown, but almost all still answer an
    /// NBSTAT query on UDP 137 with their actual computer name.
    private func resolveNetBIOSName(for ip: String) {
        guard !queriedNetBIOSIPs.contains(ip) else { return }
        queriedNetBIOSIPs.insert(ip)
        Task {
            guard let name = await NetBIOSResolver.resolveName(host: ip) else { return }
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

    /// Devices we could put any kind of name to — hostname, Bonjour, or at
    /// least a MAC vendor, plus the "Это устройство"/"Роутер" placeholders —
    /// float to the top, alphabetically among themselves; fully anonymous
    /// IP-only entries stay below, sorted by address.
    private func sortDevices() {
        devices.sort { lhs, rhs in
            let lhsNamed = lhs.hostname != nil || lhs.bonjourName != nil || lhs.macVendor != nil
            let rhsNamed = rhs.hostname != nil || rhs.bonjourName != nil || rhs.macVendor != nil
            if lhsNamed != rhsNamed { return lhsNamed }
            if lhsNamed {
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.ipAddress.localizedStandardCompare(rhs.ipAddress) == .orderedAscending
        }
    }
}
