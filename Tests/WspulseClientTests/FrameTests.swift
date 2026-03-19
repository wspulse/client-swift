import WspulseClient
import XCTest

final class FrameTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testRoundTripAllFields() throws {
        let frame = Frame(
            id: "abc-123",
            event: "chat.message",
            payload: .object([
                "text": .string("hello"),
                "count": .number(42),
                "active": .bool(true),
            ])
        )
        let data = try encoder.encode(frame)
        let decoded = try decoder.decode(Frame.self, from: data)
        XCTAssertEqual(decoded, frame)
    }

    func testRoundTripNilFields() throws {
        let frame = Frame()
        let data = try encoder.encode(frame)
        let decoded = try decoder.decode(Frame.self, from: data)
        XCTAssertNil(decoded.id)
        XCTAssertNil(decoded.event)
        XCTAssertNil(decoded.payload)
    }

    func testRoundTripPartialFields() throws {
        let frame = Frame(event: "ping")
        let data = try encoder.encode(frame)
        let decoded = try decoder.decode(Frame.self, from: data)
        XCTAssertNil(decoded.id)
        XCTAssertEqual(decoded.event, "ping")
        XCTAssertNil(decoded.payload)
    }

    func testAnyJSONNull() throws {
        let json: AnyJSON = .null
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
        XCTAssertTrue(decoded.isNull)
    }

    func testAnyJSONBool() throws {
        let json: AnyJSON = .bool(true)
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
        XCTAssertEqual(decoded.boolValue, true)
    }

    func testAnyJSONNumber() throws {
        let json: AnyJSON = .number(3.14)
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
        XCTAssertEqual(decoded.numberValue, 3.14)
    }

    func testAnyJSONString() throws {
        let json: AnyJSON = .string("hello")
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
        XCTAssertEqual(decoded.stringValue, "hello")
    }

    func testAnyJSONArray() throws {
        let json: AnyJSON = .array([.number(1), .string("two"), .bool(false)])
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
        XCTAssertEqual(decoded.arrayValue?.count, 3)
    }

    func testAnyJSONObject() throws {
        let json: AnyJSON = .object(["key": .string("value"), "num": .number(99)])
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
        XCTAssertEqual(decoded.objectValue?["key"]?.stringValue, "value")
    }

    func testAnyJSONNestedStructure() throws {
        let json: AnyJSON = .object([
            "users": .array([
                .object(["name": .string("Alice"), "age": .number(30)]),
                .object(["name": .string("Bob"), "age": .null]),
            ]),
        ])
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
    }

    func testAnyJSONLiteralExpressions() {
        let null: AnyJSON = nil
        XCTAssertEqual(null, .null)

        let bool: AnyJSON = true
        XCTAssertEqual(bool, .bool(true))

        let int: AnyJSON = 42
        XCTAssertEqual(int, .number(42))

        let float: AnyJSON = 3.14
        XCTAssertEqual(float, .number(3.14))

        let string: AnyJSON = "hello"
        XCTAssertEqual(string, .string("hello"))

        let array: AnyJSON = [1, "two", true]
        XCTAssertEqual(array, .array([.number(1), .string("two"), .bool(true)]))

        let dict: AnyJSON = ["key": "value"]
        XCTAssertEqual(dict, .object(["key": .string("value")]))
    }

    func testDecodesFromWireJSON() throws {
        let jsonString = #"{"id":"x1","event":"msg","payload":{"text":"hi"}}"#
        let data = jsonString.data(using: .utf8)!
        let frame = try decoder.decode(Frame.self, from: data)
        XCTAssertEqual(frame.id, "x1")
        XCTAssertEqual(frame.event, "msg")
        XCTAssertEqual(frame.payload, .object(["text": .string("hi")]))
    }
}
