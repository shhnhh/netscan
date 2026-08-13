import XCTest
@testable import NetScan

final class PlatformGuesserTests: XCTestCase {
    func testMacVendorOverridesToIoT() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.macVendor = "Espressif"
        XCTAssertEqual(PlatformGuesser.guess(for: device), .iot)
    }

    func testMacVendorOverridesToGameConsole() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.macVendor = "Nintendo"
        XCTAssertEqual(PlatformGuesser.guess(for: device), .gameConsole)
    }

    func testPrinterPortsAreRecognized() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.openPorts = [631]
        XCTAssertEqual(PlatformGuesser.guess(for: device), .printer)
    }

    func testLockdownPortIsRecognizedAsApple() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.openPorts = [62078]
        XCTAssertEqual(PlatformGuesser.guess(for: device), .apple)
    }

    func testAirPlayReceiverPortIsMediaDeviceNotApple() {
        // Port 7000 is opened by things being cast *to* (TVs/projectors),
        // not by the casting Apple device itself.
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.openPorts = [7000]
        XCTAssertEqual(PlatformGuesser.guess(for: device), .mediaDevice)
    }

    func testAndroidNameIsRecognized() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.bonjourName = "John's Samsung Galaxy"
        XCTAssertEqual(PlatformGuesser.guess(for: device), .android)
    }

    func testWindowsPortComboIsRecognized() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.openPorts = [139, 445]
        XCTAssertEqual(PlatformGuesser.guess(for: device), .windows)
    }

    func testUnknownWithNoSignals() {
        let device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        XCTAssertEqual(PlatformGuesser.guess(for: device), .unknown)
    }

    func testRouterVendorIsNetworkGear() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.macVendor = "TP-Link"
        XCTAssertEqual(PlatformGuesser.guess(for: device), .networkGear)
    }

    func testXboxNameIsGameConsole() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.bonjourName = "Fedor's Xbox Series X"
        XCTAssertEqual(PlatformGuesser.guess(for: device), .gameConsole)
    }

    func testPlayStationNameIsGameConsole() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.hostname = "PS5-1234"
        XCTAssertEqual(PlatformGuesser.guess(for: device), .gameConsole)
    }

    func testSamsungWithSSDPIsMediaDevice() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.macVendor = "Samsung"
        device.ssdpLocation = "http://1.1.1.1:7676/description.xml"
        XCTAssertEqual(PlatformGuesser.guess(for: device), .mediaDevice)
    }

    func testSamsungWithoutSSDPIsNotMediaDevice() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.macVendor = "Samsung"
        XCTAssertNotEqual(PlatformGuesser.guess(for: device), .mediaDevice)
    }

    func testAmazonVendorFallsBackToIoT() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.macVendor = "Amazon"
        XCTAssertEqual(PlatformGuesser.guess(for: device), .iot)
    }

    func testMicrosoftVendorFallsBackToWindows() {
        var device = Device(id: "1.1.1.1", ipAddress: "1.1.1.1")
        device.macVendor = "Microsoft"
        XCTAssertEqual(PlatformGuesser.guess(for: device), .windows)
    }
}
