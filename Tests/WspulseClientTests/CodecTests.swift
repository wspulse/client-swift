import WspulseClient
import XCTest

final class CodecTests: XCTestCase {
    private let codec = JSONCodec()

    func testFrameTypeIsText() {
        XCTAssertEqual(codec.frameType, .text)
    }

    func testEncodeDecodeRoundTrip() throws {
        let frame = Frame(id: "1", event: "test", payload: .string("data"))
        let data = try codec.encode(frame)
        let decoded = try codec.decode(data)
        XCTAssertEqual(decoded, frame)
    }

    func testEncodeDecodeEmptyFrame() throws {
        let frame = Frame()
        let data = try codec.encode(frame)
        let decoded = try codec.decode(data)
        XCTAssertNil(decoded.id)
        XCTAssertNil(decoded.event)
        XCTAssertNil(decoded.payload)
    }

    func testEncodeProducesValidJSON() throws {
        let frame = Frame(event: "ping")
        let data = try codec.encode(frame)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["event"] as? String, "ping")
    }

    func testDecodeInvalidDataThrows() {
        let badData = Data("not-json".utf8)
        XCTAssertThrowsError(try codec.decode(badData))
    }

    func testEncodeDecodeComplexPayload() throws {
        let frame = Frame(
            id: "abc",
            event: "data",
            payload: .object([
                "numbers": .array([.number(1), .number(2), .number(3)]),
                "nested": .object(["key": .bool(true)]),
            ])
        )
        let data = try codec.encode(frame)
        let decoded = try codec.decode(data)
        XCTAssertEqual(decoded, frame)
    }
}
