import XCTest
@testable import NetScan

final class NetworkInfoTests: XCTestCase {
    func testHostAddressesForSlash24() {
        let local = NetworkInfo.LocalAddress(ip: "192.168.1.50", subnetMask: "255.255.255.0")
        let hosts = NetworkInfo.hostAddresses(in: local)
        XCTAssertEqual(hosts.count, 254)
        XCTAssertEqual(hosts.first, "192.168.1.1")
        XCTAssertEqual(hosts.last, "192.168.1.254")
    }

    func testHostAddressesRespectsMaxHostsCap() {
        let local = NetworkInfo.LocalAddress(ip: "10.0.0.5", subnetMask: "255.255.0.0") // /16
        let hosts = NetworkInfo.hostAddresses(in: local, maxHosts: 10)
        XCTAssertEqual(hosts.count, 10)
    }

    // Regression test for the user's real network: gateway at the *last*
    // usable address of a /24 (10.10.19.254), not the first.
    func testGatewayGuessesForCarrierStyleSlash24() {
        let local = NetworkInfo.LocalAddress(ip: "10.10.19.37", subnetMask: "255.255.255.0")
        let guesses = NetworkInfo.gatewayGuesses(for: local)
        XCTAssertEqual(guesses, ["10.10.19.1", "10.10.19.254"])
    }

    func testGatewayGuessesForSlash30() {
        let local = NetworkInfo.LocalAddress(ip: "192.168.1.1", subnetMask: "255.255.255.252")
        let guesses = NetworkInfo.gatewayGuesses(for: local)
        XCTAssertEqual(guesses, ["192.168.1.1", "192.168.1.2"])
    }

    // A /31 point-to-point link has no usable host range under this scheme
    // (network and broadcast are adjacent) — must come back empty, not crash.
    func testGatewayGuessesForSlash31IsEmpty() {
        let local = NetworkInfo.LocalAddress(ip: "192.168.1.1", subnetMask: "255.255.255.254")
        XCTAssertEqual(NetworkInfo.gatewayGuesses(for: local), [])
    }

    func testHostAddressesWithGarbageInputReturnsEmpty() {
        let local = NetworkInfo.LocalAddress(ip: "not-an-ip", subnetMask: "255.255.255.0")
        XCTAssertEqual(NetworkInfo.hostAddresses(in: local), [])
    }
}
