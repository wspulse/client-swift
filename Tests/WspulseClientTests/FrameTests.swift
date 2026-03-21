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

    // MARK: - AnyJSON convenience accessor wrong-type returns nil

    func testAnyJSONStringValueReturnsNilForNonString() {
        XCTAssertNil(AnyJSON.number(42).stringValue)
        XCTAssertNil(AnyJSON.bool(true).stringValue)
        XCTAssertNil(AnyJSON.null.stringValue)
        XCTAssertNil(AnyJSON.array([]).stringValue)
        XCTAssertNil(AnyJSON.object([:]).stringValue)
    }

    func testAnyJSONNumberValueReturnsNilForNonNumber() {
        XCTAssertNil(AnyJSON.string("hi").numberValue)
        XCTAssertNil(AnyJSON.bool(true).numberValue)
        XCTAssertNil(AnyJSON.null.numberValue)
    }

    func testAnyJSONBoolValueReturnsNilForNonBool() {
        XCTAssertNil(AnyJSON.string("hi").boolValue)
        XCTAssertNil(AnyJSON.number(1).boolValue)
        XCTAssertNil(AnyJSON.null.boolValue)
    }

    func testAnyJSONArrayValueReturnsNilForNonArray() {
        XCTAssertNil(AnyJSON.string("hi").arrayValue)
        XCTAssertNil(AnyJSON.object([:]).arrayValue)
        XCTAssertNil(AnyJSON.null.arrayValue)
    }

    func testAnyJSONObjectValueReturnsNilForNonObject() {
        XCTAssertNil(AnyJSON.string("hi").objectValue)
        XCTAssertNil(AnyJSON.array([]).objectValue)
        XCTAssertNil(AnyJSON.null.objectValue)
    }

    func testAnyJSONIsNullReturnsFalseForNonNull() {
        XCTAssertFalse(AnyJSON.string("hi").isNull)
        XCTAssertFalse(AnyJSON.number(0).isNull)
        XCTAssertFalse(AnyJSON.bool(false).isNull)
        XCTAssertFalse(AnyJSON.array([]).isNull)
        XCTAssertFalse(AnyJSON.object([:]).isNull)
    }

    // MARK: - Frame equatable

    func testFrameEquality() {
        let frame1 = Frame(id: "1", event: "msg", payload: .string("hi"))
        let frame2 = Frame(id: "1", event: "msg", payload: .string("hi"))
        XCTAssertEqual(frame1, frame2)
    }

    func testFrameInequality() {
        let frame1 = Frame(id: "1", event: "msg", payload: .string("hi"))
        let frame2 = Frame(id: "2", event: "msg", payload: .string("hi"))
        XCTAssertNotEqual(frame1, frame2)
    }

    // MARK: - AnyJSON empty containers

    func testAnyJSONEmptyArray() throws {
        let json: AnyJSON = .array([])
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
        XCTAssertEqual(decoded.arrayValue?.count, 0)
    }

    func testAnyJSONEmptyObject() throws {
        let json: AnyJSON = .object([:])
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
        XCTAssertEqual(decoded.objectValue?.count, 0)
    }

    // MARK: - Decodes from minimal wire JSON

    func testDecodesEmptyWireJSON() throws {
        let data = Data("{}".utf8)
        let frame = try decoder.decode(Frame.self, from: data)
        XCTAssertNil(frame.id)
        XCTAssertNil(frame.event)
        XCTAssertNil(frame.payload)
    }
}
