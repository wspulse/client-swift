import WspulseClient
import XCTest

final class CodecTests: XCTestCase {
    private let codec = JSONCodec()

    func testWireTypeIsText() {
        XCTAssertEqual(codec.wireType, .text)
    }

    func testEncodeDecodeRoundTrip() throws {
        let message = Message(event: "test", payload: .string("data"))
        let data = try codec.encode(message)
        let decoded = try codec.decode(data)
        XCTAssertEqual(decoded, message)
    }

    func testEncodeDecodeEmptyMessage() throws {
        let message = Message()
        let data = try codec.encode(message)
        let decoded = try codec.decode(data)
        XCTAssertNil(decoded.event)
        XCTAssertNil(decoded.payload)
    }

    func testEncodeProducesValidJSON() throws {
        let message = Message(event: "ping")
        let data = try codec.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["event"] as? String, "ping")
    }

    func testDecodeInvalidDataThrows() {
        let badData = Data("not-json".utf8)
        XCTAssertThrowsError(try codec.decode(badData))
    }

    func testEncodeDecodeComplexPayload() throws {
        let message = Message(
            event: "data",
            payload: .object([
                "numbers": .array([.number(1), .number(2), .number(3)]),
                "nested": .object(["key": .bool(true)]),
            ])
        )
        let data = try codec.encode(message)
        let decoded = try codec.decode(data)
        XCTAssertEqual(decoded, message)
    }

    func testEncodeProducesUTF8Data() throws {
        let message = Message(event: "test", payload: .string("日本語"))
        let data = try codec.encode(message)
        let str = String(data: data, encoding: .utf8)
        XCTAssertNotNil(str, "Encoded data must be valid UTF-8")
        XCTAssertTrue(str!.contains("日本語"))
    }

    func testDecodePartialMessageKeepsNils() throws {
        let json = #"{"event":"ping"}"#
        let data = json.data(using: .utf8)!
        let message = try codec.decode(data)
        XCTAssertEqual(message.event, "ping")
        XCTAssertNil(message.payload)
    }

    func testCustomBinaryCodecWireType() {
        let binaryCodec = StubBinaryCodec()
        XCTAssertEqual(binaryCodec.wireType, .binary)
    }

    func testCustomCodecRoundTrip() throws {
        let binaryCodec = StubBinaryCodec()
        let message = Message(event: "data", payload: .string("b1"))
        let encoded = try binaryCodec.encode(message)
        let decoded = try binaryCodec.decode(encoded)
        XCTAssertEqual(decoded, message)
    }
}

/// Stub binary codec for testing the codec protocol.
private struct StubBinaryCodec: WspulseCodec {
    var wireType: WireType { .binary }

    func encode(_ message: Message) throws -> Data {
        try JSONEncoder().encode(message)
    }

    func decode(_ data: Data) throws -> Message {
        try JSONDecoder().decode(Message.self, from: data)
    }
}
