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

    /// One open port -> one finding. Kept as data so the list is easy to scan
    /// and extend. Only ports our TCP scanner can actually reach are here
    /// (UDP-only services like SNMP/SSDP are out of scope for a TCP probe).
    private struct PortRule {
        let port: Int
        let severity: FindingSeverity
        let title: String
        let detail: String
    }

    private static let portRules: [PortRule] = [
        PortRule(port: 23, severity: .critical, title: "Открыт Telnet (23)",
                 detail: "Передаёт данные и пароли без шифрования, часто с заводскими учётками. Отключи или замени на SSH."),
        PortRule(port: 2323, severity: .critical, title: "Открыт Telnet на 2323",
                 detail: "Нестандартный Telnet — типовая цель ботнета Mirai для IoT-устройств с заводскими паролями. Крайне желательно отключить."),
        PortRule(port: 5555, severity: .critical, title: "Открыт ADB (5555)",
                 detail: "Android Debug Bridge по сети без пароля = полный удалённый доступ к устройству (установка приложений, шелл). Немедленно отключи отладку по сети."),
        PortRule(port: 5900, severity: .critical, title: "Открыт VNC (5900)",
                 detail: "Удалённый доступ к экрану нередко настраивают вообще без пароля. Проверь и включи авторизацию."),
        PortRule(port: 5901, severity: .critical, title: "Открыт VNC (5901)",
                 detail: "Дополнительный дисплей VNC — тот же риск удалённого доступа к экрану без пароля."),
        PortRule(port: 6379, severity: .critical, title: "Открыт Redis (6379)",
                 detail: "По умолчанию работает без пароля. Если торчит в сеть — любой в этом Wi-Fi может читать и стирать базу."),
        PortRule(port: 27017, severity: .critical, title: "Открыт MongoDB (27017)",
                 detail: "Нередко разворачивают без авторизации — тогда данные доступны кому угодно в сети."),
        PortRule(port: 9200, severity: .critical, title: "Открыт Elasticsearch (9200)",
                 detail: "Часто поднимают вообще без аутентификации — весь индекс данных читается и меняется по сети. Классика утечек."),
        PortRule(port: 11211, severity: .critical, title: "Открыт Memcached (11211)",
                 detail: "Обычно без авторизации; вдобавок используется для DDoS-амплификации. Не должен торчать в сеть."),
        PortRule(port: 5984, severity: .warning, title: "Открыт CouchDB (5984)",
                 detail: "База данных доступна по сети. Проверь, что включена авторизация и это не 'admin party' режим."),
        PortRule(port: 21, severity: .warning, title: "Открыт FTP (21)",
                 detail: "Логин и файлы передаются в открытом виде. Проверь, не разрешён ли анонимный доступ."),
        PortRule(port: 3389, severity: .warning, title: "Открыт RDP (3389)",
                 detail: "Частая цель перебора паролей. Держи выключенным, если реально не пользуешься удалённым рабочим столом."),
        PortRule(port: 445, severity: .warning, title: "Открыт SMB (445)",
                 detail: "Протокол общих папок Windows — уязвим к EternalBlue/WannaCry-подобным атакам на непропатченных системах."),
        PortRule(port: 3306, severity: .warning, title: "Открыт MySQL (3306)",
                 detail: "База данных доступна по сети. Убедись, что это осознанно и закрыто паролем/файрволом."),
        PortRule(port: 1433, severity: .warning, title: "Открыт MSSQL (1433)",
                 detail: "База данных доступна по сети — частая цель перебора пароля sa."),
        PortRule(port: 5432, severity: .warning, title: "Открыт PostgreSQL (5432)",
                 detail: "База данных доступна по сети. Убедись, что доступ ограничен и защищён паролем."),
        PortRule(port: 8291, severity: .warning, title: "Открыт MikroTik Winbox (8291)",
                 detail: "Панель управления роутером MikroTik. Была под массовыми атаками (CVE-2018-14847) — обнови RouterOS и не открывай наружу."),
        PortRule(port: 6000, severity: .warning, title: "Открыт X11 (6000)",
                 detail: "Графический сервер X11 по сети без контроля доступа позволяет перехватывать ввод и снимать экран. Закрой доступ (xhost)."),
        PortRule(port: 135, severity: .info, title: "Открыт MSRPC (135)",
                 detail: "Служба RPC Windows. Сама по себе норм внутри сети, но наружу открывать не стоит."),
        PortRule(port: 139, severity: .info, title: "Открыт NetBIOS (139)",
                 detail: "Старый протокол общего доступа Windows. Обычно идёт в паре с SMB — проверь актуальность."),
        PortRule(port: 9100, severity: .info, title: "Открыт RAW-принтер (9100)",
                 detail: "Обычно это сетевой принтер, на который можно слать задания печати напрямую. Проверь, что устройство ожидаемое."),
        PortRule(port: 5601, severity: .info, title: "Открыт Kibana (5601)",
                 detail: "Веб-панель к Elasticsearch. Если без авторизации — открывает доступ к данным. Проверь, что закрыта."),
    ]

    /// Substring-in-banner -> finding. Signatures for services whose banner
    /// reveals a specifically dangerous build. Matched case-insensitively.
    private struct VulnSignature {
        let needle: String
        let severity: FindingSeverity
        let title: String
        let detail: String
    }

    private static let vulnSignatures: [VulnSignature] = [
        VulnSignature(needle: "vsftpd 2.3.4", severity: .critical,
                      title: "vsFTPd 2.3.4 — версия с бэкдором",
                      detail: "У этой конкретной сборки vsFTPd известный бэкдор (CVE-2011-2523), дающий шелл. Срочно обнови FTP-сервер."),
        VulnSignature(needle: "proftpd 1.3.3", severity: .warning,
                      title: "ProFTPD 1.3.3 — уязвимая версия",
                      detail: "Известны RCE-уязвимости в этой ветке ProFTPD. Обнови до актуальной версии."),
        VulnSignature(needle: "openssh_4.", severity: .info,
                      title: "Очень старый OpenSSH",
                      detail: "Версия OpenSSH из ветки 4.x давно устарела и содержит известные уязвимости. Обнови."),
        VulnSignature(needle: "openssh_5.", severity: .info,
                      title: "Устаревший OpenSSH (5.x)",
                      detail: "Ветка OpenSSH 5.x устарела. Рекомендуется обновление."),
        VulnSignature(needle: "openssh_6.", severity: .info,
                      title: "Устаревший OpenSSH (6.x)",
                      detail: "Ветка OpenSSH 6.x устарела. Рекомендуется обновление."),
        VulnSignature(needle: "apache/2.2", severity: .info,
                      title: "Устаревший Apache (2.2)",
                      detail: "Apache httpd 2.2 снят с поддержки. Проверь обновления веб-сервера."),
        VulnSignature(needle: "microsoft-iis/6", severity: .info,
                      title: "Устаревший IIS 6.0",
                      detail: "IIS 6.0 (Windows Server 2003) давно не поддерживается и небезопасен."),
        VulnSignature(needle: "boa/0.9", severity: .warning,
                      title: "Веб-сервер Boa (часто в IoT/камерах)",
                      detail: "Boa — заброшенный встраиваемый веб-сервер, типичен для дешёвых камер/роутеров с известными дырами."),
    ]

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

        for rule in portRules where portSet.contains(rule.port) {
            findings.append(SecurityFinding(
                severity: rule.severity, title: rule.title, detail: rule.detail, port: rule.port))
        }

        for signature in vulnSignatures where bannerText.contains(signature.needle) {
            findings.append(SecurityFinding(
                severity: signature.severity, title: signature.title, detail: signature.detail, port: nil))
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
