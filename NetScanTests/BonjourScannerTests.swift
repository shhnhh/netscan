import XCTest
@testable import NetScan

final class BonjourScannerTests: XCTestCase {
    // Regression test: AirPlay/RAOP names the service "<12-hex-id>@name",
    // e.g. "682F678C480A@MacBook" — this isn't garbled encoding, it's the
    // protocol's own convention, and the prefix should be stripped.
    func testCleanServiceNameStripsAirPlayIDPrefix() {
        XCTAssertEqual(BonjourScanner.cleanServiceName("682F678C480A@MacBook"), "MacBook")
    }

    func testCleanServiceNameLeavesPlainNamesAlone() {
        XCTAssertEqual(BonjourScanner.cleanServiceName("Fedor's iPhone"), "Fedor's iPhone")
    }

    func testCleanServiceNameLeavesNonHexPrefixAlone() {
        // Only 12 hex digits followed by "@" counts — anything else that
        // merely contains an "@" must be left untouched.
        XCTAssertEqual(BonjourScanner.cleanServiceName("not-hex-12@Name"), "not-hex-12@Name")
    }

    func testCleanServiceNameLeavesWrongLengthPrefixAlone() {
        XCTAssertEqual(BonjourScanner.cleanServiceName("ABCDEF@Name"), "ABCDEF@Name")
    }

    // Regression test: Network.framework stringifies interface-bound
    // addresses as "1.2.3.4%en0", which broke matching against the
    // plain-IP device list.
    func testPlainAddressStripsInterfaceSuffix() {
        XCTAssertEqual(BonjourScanner.plainAddress("192.168.1.5%en0"), "192.168.1.5")
    }

    func testPlainAddressLeavesPlainIPAlone() {
        XCTAssertEqual(BonjourScanner.plainAddress("10.0.0.1"), "10.0.0.1")
    }
}
