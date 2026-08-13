import XCTest
@testable import NetScan

final class ICMPPingerTests: XCTestCase {
    // Regression test for the "512 devices" bug: an Echo Reply (type 0) must
    // be recognized whether or not the kernel prepended an IPv4 header, and
    // anything else (e.g. type 3 Destination Unreachable, or an Echo
    // Request) must not be.
    func testEchoReplyWithoutIPHeader() {
        let packet: [UInt8] = [0, 0, 0xFF, 0xFF, 0, 0, 0, 0]
        XCTAssertTrue(ICMPPinger.isEchoReply(buffer: packet, count: packet.count))
    }

    func testEchoReplyWithIPHeaderPrepended() {
        var ipHeader = [UInt8](repeating: 0, count: 20)
        ipHeader[0] = 0x45 // version 4, IHL 5 (20-byte header)
        let icmpBody: [UInt8] = [0, 0, 0xFF, 0xFF, 0, 0, 0, 0]
        let packet = ipHeader + icmpBody
        XCTAssertTrue(ICMPPinger.isEchoReply(buffer: packet, count: packet.count))
    }

    func testDestinationUnreachableIsNotAnEchoReply() {
        // type 3 = Destination Unreachable — this is exactly the stray
        // packet that used to get miscounted as "host is alive".
        let packet: [UInt8] = [3, 1, 0, 0, 0, 0, 0, 0]
        XCTAssertFalse(ICMPPinger.isEchoReply(buffer: packet, count: packet.count))
    }

    func testEchoRequestIsNotAnEchoReply() {
        var ipHeader = [UInt8](repeating: 0, count: 20)
        ipHeader[0] = 0x45
        let icmpBody: [UInt8] = [8, 0, 0, 0, 0, 0, 0, 0] // type 8 = Echo Request
        let packet = ipHeader + icmpBody
        XCTAssertFalse(ICMPPinger.isEchoReply(buffer: packet, count: packet.count))
    }

    func testEmptyBufferIsNotAnEchoReply() {
        XCTAssertFalse(ICMPPinger.isEchoReply(buffer: [], count: 0))
    }

    func testMakeEchoPacketShape() {
        let packet = ICMPPinger.makeEchoPacket(identifier: 0x1234, sequence: 1)
        XCTAssertEqual(packet[0], 8) // type: Echo Request
        XCTAssertEqual(packet[1], 0) // code
        XCTAssertEqual(packet.count, 8 + "netscan".utf8.count)
    }

    // The checksum field the packet ships with must be exactly what
    // recomputing the checksum over the same bytes (with that field zeroed)
    // produces — this is the property a receiving host actually verifies.
    func testChecksumRoundTrips() {
        let packet = ICMPPinger.makeEchoPacket(identifier: 0xABCD, sequence: 7)
        let shippedChecksum = (UInt16(packet[2]) << 8) | UInt16(packet[3])

        var zeroed = packet
        zeroed[2] = 0
        zeroed[3] = 0
        let recomputed = ICMPPinger.icmpChecksum(zeroed)

        XCTAssertEqual(shippedChecksum, recomputed)
    }
}
