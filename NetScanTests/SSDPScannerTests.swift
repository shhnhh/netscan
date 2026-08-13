import XCTest
@testable import NetScan

final class SSDPScannerTests: XCTestCase {
    private let sampleResponse = [
        "HTTP/1.1 200 OK",
        "CACHE-CONTROL: max-age=100",
        "LOCATION: http://192.168.1.5:80/desc.xml",
        "SERVER: Linux/1.0 UPnP/1.0",
        "ST: upnp:rootdevice",
        "", "",
    ].joined(separator: "\r\n")

    func testExtractHeaderFindsValue() {
        XCTAssertEqual(SSDPScanner.extractHeader("LOCATION", from: sampleResponse), "http://192.168.1.5:80/desc.xml")
    }

    func testExtractHeaderIsCaseInsensitive() {
        XCTAssertEqual(SSDPScanner.extractHeader("location", from: sampleResponse), "http://192.168.1.5:80/desc.xml")
        XCTAssertEqual(SSDPScanner.extractHeader("Location", from: sampleResponse), "http://192.168.1.5:80/desc.xml")
    }

    func testExtractHeaderReturnsNilWhenMissing() {
        XCTAssertNil(SSDPScanner.extractHeader("USN", from: sampleResponse))
    }
}
