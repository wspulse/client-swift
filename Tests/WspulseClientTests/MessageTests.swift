import WspulseClient
import XCTest

final class MessageTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testRoundTripAllFields() throws {
        let message = Message(
            event: "chat.message",
            payload: .object([
                "text": .string("hello"),
                "count": .number(42),
                "active": .bool(true),
            ])
        )
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(Message.self, from: data)
        XCTAssertEqual(decoded, message)
    }

    func testRoundTripNilFields() throws {
        let message = Message()
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(Message.self, from: data)
        XCTAssertNil(decoded.event)
        XCTAssertNil(decoded.payload)
    }

    func testRoundTripPartialFields() throws {
        let message = Message(event: "ping")
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(Message.self, from: data)
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
            ])
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
        let jsonString = #"{"event":"msg","payload":{"text":"hi"}}"#
        let data = jsonString.data(using: .utf8)!
        let message = try decoder.decode(Message.self, from: data)
        XCTAssertEqual(message.event, "msg")
        XCTAssertEqual(message.payload, .object(["text": .string("hi")]))
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

    // MARK: - Message equatable

    func testMessageEquality() {
        let message1 = Message(event: "msg", payload: .string("hi"))
        let message2 = Message(event: "msg", payload: .string("hi"))
        XCTAssertEqual(message1, message2)
    }

    func testMessageInequality() {
        let message1 = Message(event: "msg", payload: .string("hi"))
        let message2 = Message(event: "other", payload: .string("hi"))
        XCTAssertNotEqual(message1, message2)
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
        let message = try decoder.decode(Message.self, from: data)
        XCTAssertNil(message.event)
        XCTAssertNil(message.payload)
    }

    // MARK: - Payload-only message round-trip

    func testPayloadOnlyMessageRoundTrip() throws {
        let message = Message(payload: .array([.number(1), .number(2)]))
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(Message.self, from: data)
        XCTAssertNil(decoded.event)
        XCTAssertEqual(decoded.payload, .array([.number(1), .number(2)]))
    }

    // MARK: - AnyJSON unsupported type decode throws

    func testAnyJSONUnsupportedTypeThrows() {
        // An empty JSON array decoded as a single AnyJSON is valid,
        // but something like a top-level fragment that isn't any known type
        // would throw. We can test with Data that is e.g. a bare CBOR-like value.
        // The easiest trigger is to feed a JSON fragment the decoder can't map.
        // Note: Any valid JSON can be decoded. The error path triggers for
        // non-JSON or types not matchable. We use raw bytes that pass JSON
        // parsing but map to a type Codable can't resolve through the fallback.
        // Actually: all valid JSON maps to AnyJSON. The error path can only
        // trigger with custom decoders. We verify the path exists by decoding
        // invalid JSON instead.
        let invalidData = Data("#invalid#".utf8)
        XCTAssertThrowsError(try decoder.decode(AnyJSON.self, from: invalidData))
    }

    // MARK: - AnyJSON bool false round-trip

    func testAnyJSONBoolFalseRoundTrip() throws {
        let json: AnyJSON = .bool(false)
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
        XCTAssertEqual(decoded.boolValue, false)
    }

    // MARK: - AnyJSON negative number round-trip

    func testAnyJSONNegativeNumberRoundTrip() throws {
        let json: AnyJSON = .number(-42.5)
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
        XCTAssertEqual(decoded.numberValue, -42.5)
    }

    // MARK: - AnyJSON empty string round-trip

    func testAnyJSONEmptyStringRoundTrip() throws {
        let json: AnyJSON = .string("")
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
        XCTAssertEqual(decoded.stringValue, "")
    }

    // MARK: - AnyJSON unicode string round-trip

    func testAnyJSONUnicodeStringRoundTrip() throws {
        let json: AnyJSON = .string("日本語🎉émojis")
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
    }

    // MARK: - AnyJSON deeply nested structure

    func testAnyJSONDeeplyNestedRoundTrip() throws {
        let json: AnyJSON = .object([
            "level1": .object([
                "level2": .array([
                    .object(["level3": .string("deep")])
                ])
            ])
        ])
        let data = try encoder.encode(json)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, json)
    }

    // MARK: - Message inequality on different fields

    func testMessageInequalityOnEvent() {
        let message1 = Message(event: "msg", payload: .string("a"))
        let message2 = Message(event: "other", payload: .string("a"))
        XCTAssertNotEqual(message1, message2)
    }

    func testMessageInequalityOnPayload() {
        let message1 = Message(event: "msg", payload: .string("a"))
        let message2 = Message(event: "msg", payload: .string("b"))
        XCTAssertNotEqual(message1, message2)
    }

    func testMessageInequalityNilVsNonNil() {
        let message1 = Message(event: "msg")
        let message2 = Message(event: "msg", payload: .null)
        XCTAssertNotEqual(message1, message2)
    }
}
