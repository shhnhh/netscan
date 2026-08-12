import Foundation

/// Rule-based heuristics over open ports and grabbed banners — no CVE
/// database, no active exploitation, no credential attempts. Same spirit as
/// what Fing/nmap's default scripts do: flag things that are commonly
/// misconfigured (open Telnet, database with no auth wall, etc.) and let the
/// person decide what to do about their own network.
enum SecurityAnalyzer {
    struct Analysis {
        let findings: [SecurityFinding]
        let isCamera: Bool
        let cameraVendor: String?
    }

    private static let cameraPorts: Set<Int> = [554, 8554, 34567, 37777, 37778]
    private static let rtspPorts: Set<Int> = [554, 8554]

    private static let cameraVendorStrings: [(needle: String, vendor: String)] = [
        ("hikvision", "Hikvision"),
        ("dahua", "Dahua"),
        ("xiongmai", "Xiongmai/generic DVR"),
        ("foscam", "Foscam"),
        ("reolink", "Reolink"),
        ("amcrest", "Amcrest"),
        ("axis", "Axis"),
        ("wyze", "Wyze"),
        ("dvr", "DVR/NVR"),
        ("nvr", "DVR/NVR"),
        ("ipcam", "IP-камера"),
        ("rtsp/1.0", "RTSP-камера"),
    ]

    static func analyze(openPorts: [Int], banners: [Int: String]) -> Analysis {
        var findings: [SecurityFinding] = []
        let portSet = Set(openPorts)
        let bannerText = banners.values.joined(separator: "\n").lowercased()

        if portSet.contains(23) {
            findings.append(SecurityFinding(
                severity: .critical,
                title: "Открыт Telnet (23)",
                detail: "Передаёт данные и пароли без шифрования, часто с заводскими учётками. Отключи или замени на SSH.",
                port: 23))
        }
        if portSet.contains(21) {
            findings.append(SecurityFinding(
                severity: .warning,
                title: "Открыт FTP (21)",
                detail: "Логин и файлы передаются в открытом виде. Проверь, не разрешён ли анонимный доступ.",
                port: 21))
        }
        if portSet.contains(5900) {
            findings.append(SecurityFinding(
                severity: .critical,
                title: "Открыт VNC (5900)",
                detail: "Удалённый доступ к экрану нередко настраивают вообще без пароля. Проверь и включи авторизацию.",
                port: 5900))
        }
        if portSet.contains(3389) {
            findings.append(SecurityFinding(
                severity: .warning,
                title: "Открыт RDP (3389)",
                detail: "Частая цель перебора паролей. Держи выключенным, если реально не пользуешься удалённым рабочим столом.",
                port: 3389))
        }
        if portSet.contains(445) {
            findings.append(SecurityFinding(
                severity: .warning,
                title: "Открыт SMB (445)",
                detail: "Протокол общих папок Windows — уязвим к EternalBlue/WannaCry-подобным атакам на непропатченных системах.",
                port: 445))
        }
        if portSet.contains(6379) {
            findings.append(SecurityFinding(
                severity: .critical,
                title: "Открыт Redis (6379)",
                detail: "По умолчанию работает без пароля. Если торчит в сеть — любой в этом Wi-Fi может читать и стирать базу.",
                port: 6379))
        }
        if portSet.contains(27017) {
            findings.append(SecurityFinding(
                severity: .critical,
                title: "Открыт MongoDB (27017)",
                detail: "Нередко разворачивают без авторизации — тогда данные доступны кому угодно в сети.",
                port: 27017))
        }
        if portSet.contains(3306) {
            findings.append(SecurityFinding(
                severity: .warning,
                title: "Открыт MySQL (3306)",
                detail: "База данных доступна по сети. Убедись, что это осознанно и закрыто паролем/файрволом.",
                port: 3306))
        }
        if portSet.contains(1433) {
            findings.append(SecurityFinding(
                severity: .warning,
                title: "Открыт MSSQL (1433)",
                detail: "База данных доступна по сети — частая цель перебора пароля sa.",
                port: 1433))
        }
        if portSet.contains(9100) {
            findings.append(SecurityFinding(
                severity: .info,
                title: "Открыт RAW-принтер (9100)",
                detail: "Обычно это сетевой принтер, на который можно слать задания печати напрямую. Проверь, что устройство ожидаемое.",
                port: 9100))
        }

        var isCamera = portSet.contains(where: cameraPorts.contains)
        var vendor: String?
        for (needle, name) in cameraVendorStrings where bannerText.contains(needle) {
            isCamera = true
            vendor = name
            break
        }

        if isCamera {
            findings.append(SecurityFinding(
                severity: .warning,
                title: vendor.map { "Похоже на камеру (\($0))" } ?? "Похоже на камеру/видеорегистратор",
                detail: "Обнаружены признаки видеонаблюдения (RTSP/DVR-порты или баннер устройства). Если это не твоя камера — стоит выяснить, откуда она в сети. Если твоя — проверь, что пароль администратора не заводской.",
                port: nil))
        }

        // A DESCRIBE request that gets back anything other than "401" means
        // the stream itself isn't behind a password — we only ever look at
        // this one status line, never the actual video/audio.
        for port in openPorts where rtspPorts.contains(port) {
            guard let banner = banners[port] else { continue }
            let statusLine = banner.split(separator: "\r\n").first.map(String.init) ?? banner
            guard statusLine.lowercased().contains("rtsp/1.0") else { continue }
            if !statusLine.contains("401") {
                findings.append(SecurityFinding(
                    severity: .critical,
                    title: "RTSP-поток похоже открыт без пароля (порт \(port))",
                    detail: "Сервер не запросил авторизацию. Если это не твоя камера — не подключайся к потоку и не смотри его, это уже будет просмотром чужого видео без разрешения; если есть возможность — сообщи владельцу или админу сети. Если твоя — срочно поставь пароль на камеру.",
                    port: port))
            }
        }

        for (port, banner) in banners {
            if let serverLine = banner
                .split(separator: "\r\n")
                .first(where: { $0.lowercased().hasPrefix("server:") }) {
                findings.append(SecurityFinding(
                    severity: .info,
                    title: "Порт \(port) раскрывает версию ПО",
                    detail: String(serverLine).trimmingCharacters(in: .whitespaces),
                    port: port))
            }
        }

        findings.sort { $0.severity > $1.severity }
        return Analysis(findings: findings, isCamera: isCamera, cameraVendor: vendor)
    }
}
