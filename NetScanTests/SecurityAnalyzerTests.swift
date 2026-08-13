import XCTest
@testable import NetScan

final class SecurityAnalyzerTests: XCTestCase {
    func testOpenTelnetProducesCriticalFinding() {
        let analysis = SecurityAnalyzer.analyze(openPorts: [23], banners: [:])
        XCTAssertTrue(analysis.findings.contains { $0.severity == .critical && $0.title.contains("Telnet") })
    }

    func testNoOpenPortsProducesNoFindings() {
        let analysis = SecurityAnalyzer.analyze(openPorts: [], banners: [:])
        XCTAssertTrue(analysis.findings.isEmpty)
        XCTAssertFalse(analysis.isCamera)
    }

    // A backdoored vsFTPd build should be flagged from the banner even
    // though the port itself (21) only warrants a lower-severity port rule —
    // findings must come back sorted with the critical one first.
    func testKnownVulnerableBannerOutranksPortRule() {
        let analysis = SecurityAnalyzer.analyze(openPorts: [21], banners: [21: "220 (vsFTPd 2.3.4)"])
        XCTAssertEqual(analysis.findings.first?.severity, .critical)
        XCTAssertTrue(analysis.findings.contains { $0.title.contains("vsFTPd 2.3.4") })
        XCTAssertTrue(analysis.findings.contains { $0.title.contains("FTP") })
    }

    func testRTSPWithoutAuthChallengeIsFlaggedCritical() {
        let analysis = SecurityAnalyzer.analyze(openPorts: [554], banners: [554: "RTSP/1.0 200 OK\r\n"])
        XCTAssertTrue(analysis.isCamera)
        XCTAssertTrue(analysis.findings.contains { $0.severity == .critical && $0.title.contains("без пароля") })
    }

    func testRTSPWithAuthChallengeIsNotFlagged() {
        let analysis = SecurityAnalyzer.analyze(openPorts: [554], banners: [554: "RTSP/1.0 401 Unauthorized\r\n"])
        XCTAssertFalse(analysis.findings.contains { $0.title.contains("без пароля") })
    }

    func testCameraVendorStringIsDetected() {
        let analysis = SecurityAnalyzer.analyze(openPorts: [80], banners: [80: "Server: Hikvision-Webs"])
        XCTAssertTrue(analysis.isCamera)
        XCTAssertEqual(analysis.cameraVendor, "Hikvision")
    }

    func testFindingsAreSortedMostSevereFirst() {
        let analysis = SecurityAnalyzer.analyze(openPorts: [135, 23, 9100], banners: [:])
        let severities = analysis.findings.map(\.severity)
        XCTAssertEqual(severities, severities.sorted(by: >))
    }
}
