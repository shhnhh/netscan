import XCTest
@testable import NetScan

final class RawPrinterTests: XCTestCase {
    func testTestPageStartsWithPJLHeader() {
        let data = RawPrinter.makeTestPage(deviceName: "Office Printer")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("\u{1B}%-12345X@PJL\r\n@PJL ENTER LANGUAGE=PCL\r\n"))
    }

    func testTestPageEndsWithFormFeedAndPJLFooter() {
        let data = RawPrinter.makeTestPage(deviceName: "Office Printer")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasSuffix("\u{0C}\u{1B}%-12345X"))
    }

    func testTestPageIncludesDeviceName() {
        let data = RawPrinter.makeTestPage(deviceName: "HP LaserJet")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("HP LaserJet"))
    }
}
