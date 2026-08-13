import XCTest
@testable import NetScan

final class DeviceTests: XCTestCase {
    // displayName priority: Bonjour name > hostname > MAC vendor > raw IP —
    // this is what actually decides what the user sees in the device list.
    func testDisplayNameFallsBackToIPWithNoOtherInfo() {
        let device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        XCTAssertEqual(device.displayName, "1.1.1.1")
    }

    func testDisplayNamePrefersVendorOverIP() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.macVendor = "Apple"
        XCTAssertEqual(device.displayName, "Apple")
    }

    func testDisplayNamePrefersHostnameOverVendor() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.macVendor = "Apple"
        device.hostname = "Fedor's iPhone"
        XCTAssertEqual(device.displayName, "Fedor's iPhone")
    }

    func testDisplayNamePrefersBonjourOverHostname() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.hostname = "some-hostname"
        device.bonjourName = "Living Room TV"
        XCTAssertEqual(device.displayName, "Living Room TV")
    }
}
