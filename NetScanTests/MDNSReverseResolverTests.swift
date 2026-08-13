import XCTest
@testable import NetScan

final class MDNSReverseResolverTests: XCTestCase {
    func testMakePTRQueryEncodesReversedOctets() {
        let packet = MDNSReverseResolver.makePTRQuery(host: "10.10.19.254")
        XCTAssertNotNil(packet)
        guard let packet else { return }

        let (name, nameEnd) = MDNSReverseResolver.decodeName(packet, 12, packet.count)!
        XCTAssertEqual(name, "254.19.10.10.in-addr.arpa")

        // QTYPE = PTR (12), QCLASS = IN (1) immediately follow the name.
        XCTAssertEqual(packet[nameEnd], 0x00)
        XCTAssertEqual(packet[nameEnd + 1], 0x0C)
        XCTAssertEqual(packet[nameEnd + 2], 0x00)
        XCTAssertEqual(packet[nameEnd + 3], 0x01)
    }

    func testMakePTRQueryRejectsGarbageHost() {
        XCTAssertNil(MDNSReverseResolver.makePTRQuery(host: "not-an-ip"))
    }

    func testDecodeNameWithLiteralLabels() {
        // "abc.local" as length-prefixed labels + terminator.
        let buffer: [UInt8] = [3, 97, 98, 99, 5, 108, 111, 99, 97, 108, 0]
        let result = MDNSReverseResolver.decodeName(buffer, 0, buffer.count)
        XCTAssertEqual(result?.0, "abc.local")
        XCTAssertEqual(result?.1, buffer.count)
    }

    func testDecodeNameFollowsCompressionPointer() {
        // Real name "host.local" at offset 0, then a second name elsewhere
        // in the "packet" that's just a pointer back to it.
        var buffer: [UInt8] = [4, 104, 111, 115, 116, 5, 108, 111, 99, 97, 108, 0] // "host.local"
        let pointerOffset = buffer.count
        buffer += [0xC0, 0x00] // pointer to offset 0

        let result = MDNSReverseResolver.decodeName(buffer, pointerOffset, buffer.count)
        XCTAssertEqual(result?.0, "host.local")
        // The pointer itself is 2 bytes — decoding it should only consume
        // those 2 bytes in the surrounding message, not jump the cursor
        // into the target it pointed at.
        XCTAssertEqual(result?.1, pointerOffset + 2)
    }

    func testDecodeNameDetectsPointerLoop() {
        // A pointer at offset 0 that points right back to itself must not
        // hang forever.
        let buffer: [UInt8] = [0xC0, 0x00]
        XCTAssertNil(MDNSReverseResolver.decodeName(buffer, 0, buffer.count))
    }

    func testParsePTRResponseStripsLocalSuffix() {
        var buffer = makeHeader(qdcount: 0, ancount: 1)
        buffer += [0x00] // answer name: empty/root name (its content is discarded by the parser anyway)
        buffer += [0x00, 0x0C] // TYPE = PTR
        buffer += [0x00, 0x01] // CLASS = IN
        buffer += [0, 0, 0, 0] // TTL
        var rdata: [UInt8] = []
        for label in ["Fedors-iPhone", "local"] {
            let bytes = Array(label.utf8)
            rdata.append(UInt8(bytes.count))
            rdata += bytes
        }
        rdata.append(0)
        buffer += bigEndian16(UInt16(rdata.count))
        buffer += rdata

        XCTAssertEqual(MDNSReverseResolver.parsePTRResponse(buffer: buffer, count: buffer.count), "Fedors-iPhone")
    }

    func testParsePTRResponseWithNoAnswersReturnsNil() {
        let buffer = makeHeader(qdcount: 0, ancount: 0)
        XCTAssertNil(MDNSReverseResolver.parsePTRResponse(buffer: buffer, count: buffer.count))
    }

    // MARK: - Helpers

    private func makeHeader(qdcount: UInt16, ancount: UInt16) -> [UInt8] {
        [0x00, 0x00, 0x00, 0x00] + bigEndian16(qdcount) + bigEndian16(ancount) + [0, 0, 0, 0]
    }

    private func bigEndian16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }
}
