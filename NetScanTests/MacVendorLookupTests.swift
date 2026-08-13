import XCTest
@testable import NetScan

final class MacVendorLookupTests: XCTestCase {
    func testKnownOUIResolves() {
        XCTAssertEqual(MacVendorLookup.vendor(for: "a4:83:e7:11:22:33"), "Apple")
    }

    func testLookupIsCaseInsensitive() {
        XCTAssertEqual(MacVendorLookup.vendor(for: "A4:83:E7:11:22:33"), "Apple")
    }

    func testUnknownOUIReturnsNil() {
        XCTAssertNil(MacVendorLookup.vendor(for: "00:00:00:11:22:33"))
    }

    func testTooShortInputReturnsNil() {
        XCTAssertNil(MacVendorLookup.vendor(for: "a4:83"))
    }
}
