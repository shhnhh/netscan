import XCTest
@testable import NetScan

final class AgentSettingsTests: XCTestCase {
    func testAddsHTTPSchemeWhenMissing() {
        XCTAssertEqual(AgentSettings.normalizeBaseURL("192.168.1.50:8756"), "http://192.168.1.50:8756")
    }

    func testLeavesExplicitHTTPSchemeAlone() {
        XCTAssertEqual(AgentSettings.normalizeBaseURL("http://192.168.1.50:8756"), "http://192.168.1.50:8756")
    }

    func testLeavesExplicitHTTPSSchemeAlone() {
        XCTAssertEqual(AgentSettings.normalizeBaseURL("https://agent.local:8756"), "https://agent.local:8756")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(AgentSettings.normalizeBaseURL("  192.168.1.50:8756  "), "http://192.168.1.50:8756")
    }

    func testEmptyHostReturnsNil() {
        XCTAssertNil(AgentSettings.normalizeBaseURL(""))
        XCTAssertNil(AgentSettings.normalizeBaseURL("   "))
    }
}
