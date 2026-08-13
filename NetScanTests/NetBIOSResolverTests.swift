import XCTest
@testable import NetScan

final class NetBIOSResolverTests: XCTestCase {
    func testMakeNBSTATQueryShape() {
        let packet = NetBIOSResolver.makeNBSTATQuery()
        // Header (12) + name length byte (1) + 32-byte encoded name +
        // terminator (1) + QTYPE (2) + QCLASS (2)
        XCTAssertEqual(packet.count, 12 + 1 + 32 + 1 + 2 + 2)
        XCTAssertEqual(packet[4], 0x00) // QDCOUNT high byte
        XCTAssertEqual(packet[5], 0x01) // QDCOUNT low byte: exactly one question
        XCTAssertEqual(packet[12], 0x20) // encoded name length
        XCTAssertEqual(packet[45], 0x00) // name terminator (12 + 1 + 32)
        XCTAssertEqual(packet[46], 0x00) // QTYPE high byte
        XCTAssertEqual(packet[47], 0x21) // QTYPE low byte: NBSTAT
    }

    func testSkipNamePointer() {
        // 0xC0 flag bits mark a compression pointer — always exactly 2 bytes.
        let buffer: [UInt8] = [0xC0, 0x0C]
        XCTAssertEqual(NetBIOSResolver.skipName(buffer, 0, buffer.count), 2)
    }

    func testSkipNameLiteralLabel() {
        // Length-prefixed label "ABC" followed by the zero terminator.
        let buffer: [UInt8] = [3, 65, 66, 67, 0]
        XCTAssertEqual(NetBIOSResolver.skipName(buffer, 0, buffer.count), 5)
    }

    func testParseNBSTATResponseExtractsWorkstationName() {
        var buffer = makeHeader(qdcount: 0, ancount: 1)
        buffer += [0xC0, 0x0C] // answer name: compression pointer
        buffer += [0x00, 0x21] // TYPE = NBSTAT
        buffer += [0x00, 0x01] // CLASS = IN
        buffer += [0, 0, 0, 0] // TTL
        let rdata = makeNodeNameTable(entries: [("TESTPC", suffix: 0x00, isGroup: false)])
        buffer += bigEndian16(UInt16(rdata.count)) // RDLENGTH
        buffer += rdata

        XCTAssertEqual(NetBIOSResolver.parseNBSTATResponse(buffer: buffer, count: buffer.count), "TESTPC")
    }

    // Workgroup/group names (the G bit set) aren't the machine's own name —
    // the parser must skip past them to find a real unique entry.
    func testParseNBSTATResponseSkipsGroupNamesForRealOne() {
        var buffer = makeHeader(qdcount: 0, ancount: 1)
        buffer += [0xC0, 0x0C]
        buffer += [0x00, 0x21]
        buffer += [0x00, 0x01]
        buffer += [0, 0, 0, 0]
        let rdata = makeNodeNameTable(entries: [
            ("WORKGROUP", suffix: 0x00, isGroup: true),
            ("REALPC", suffix: 0x00, isGroup: false),
        ])
        buffer += bigEndian16(UInt16(rdata.count))
        buffer += rdata

        XCTAssertEqual(NetBIOSResolver.parseNBSTATResponse(buffer: buffer, count: buffer.count), "REALPC")
    }

    func testParseNBSTATResponseWithEchoedQuestionSection() {
        var buffer = makeHeader(qdcount: 1, ancount: 1)
        buffer += NetBIOSResolver.makeNBSTATQuery().suffix(from: 12) // question section, reused verbatim
        buffer += [0xC0, 0x0C]
        buffer += [0x00, 0x21]
        buffer += [0x00, 0x01]
        buffer += [0, 0, 0, 0]
        let rdata = makeNodeNameTable(entries: [("HOST-A", suffix: 0x00, isGroup: false)])
        buffer += bigEndian16(UInt16(rdata.count))
        buffer += rdata

        XCTAssertEqual(NetBIOSResolver.parseNBSTATResponse(buffer: buffer, count: buffer.count), "HOST-A")
    }

    func testParseNBSTATResponseWithNoAnswersReturnsNil() {
        let buffer = makeHeader(qdcount: 0, ancount: 0)
        XCTAssertNil(NetBIOSResolver.parseNBSTATResponse(buffer: buffer, count: buffer.count))
    }

    func testParseNBSTATResponseTooShortReturnsNil() {
        XCTAssertNil(NetBIOSResolver.parseNBSTATResponse(buffer: [0, 1, 2], count: 3))
    }

    // MARK: - Helpers

    private func makeHeader(qdcount: UInt16, ancount: UInt16) -> [UInt8] {
        [0x82, 0x28, 0x00, 0x00] + bigEndian16(qdcount) + bigEndian16(ancount) + [0, 0, 0, 0]
    }

    private func bigEndian16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    /// Builds an RDATA name table: 1 count byte + 18-byte entries
    /// (15-byte space-padded name, 1 byte suffix, 2 bytes flags).
    private func makeNodeNameTable(entries: [(String, suffix: UInt8, isGroup: Bool)]) -> [UInt8] {
        var rdata: [UInt8] = [UInt8(entries.count)]
        for (name, suffix, isGroup) in entries {
            var nameBytes = Array(name.utf8)
            while nameBytes.count < 15 { nameBytes.append(0x20) } // space-padded
            rdata += nameBytes.prefix(15)
            rdata.append(suffix)
            rdata += bigEndian16(isGroup ? 0x8000 : 0x0000)
        }
        return rdata
    }
}
