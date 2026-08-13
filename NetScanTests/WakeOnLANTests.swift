import XCTest
@testable import NetScan

final class WakeOnLANTests: XCTestCase {
    func testMagicPacketShape() {
        let mac: [UInt8] = [0xA4, 0x83, 0xE7, 0x11, 0x22, 0x33]
        let packet = WakeOnLAN.makeMagicPacket(mac: "a4:83:e7:11:22:33")
        XCTAssertNotNil(packet)
        guard let packet else { return }

        XCTAssertEqual(packet.count, 6 + 16 * 6)
        XCTAssertEqual(Array(packet.prefix(6)), [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        for i in 0..<16 {
            let start = 6 + i * 6
            XCTAssertEqual(Array(packet[start..<(start + 6)]), mac)
        }
    }

    func testAcceptsDashSeparatedMAC() {
        XCTAssertNotNil(WakeOnLAN.makeMagicPacket(mac: "A4-83-E7-11-22-33"))
    }

    func testRejectsMalformedMAC() {
        XCTAssertNil(WakeOnLAN.makeMagicPacket(mac: "not-a-mac"))
        XCTAssertNil(WakeOnLAN.makeMagicPacket(mac: "a4:83:e7:11:22"))
        XCTAssertNil(WakeOnLAN.makeMagicPacket(mac: ""))
    }
}
