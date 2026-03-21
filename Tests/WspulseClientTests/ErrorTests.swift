import WspulseClient
import XCTest

final class ErrorTests: XCTestCase {
    // MARK: - Description prefix

    func testConnectionClosedDescription() {
        let error = WspulseError.connectionClosed
        XCTAssertEqual(error.description, "wspulse: connection closed")
    }

    func testSendBufferFullDescription() {
        let error = WspulseError.sendBufferFull
        XCTAssertEqual(error.description, "wspulse: send buffer full")
    }

    func testRetriesExhaustedDescription() {
        let error = WspulseError.retriesExhausted
        XCTAssertEqual(error.description, "wspulse: retries exhausted")
    }

    func testConnectionLostDescription() {
        let error = WspulseError.connectionLost
        XCTAssertEqual(error.description, "wspulse: connection lost")
    }

    func testEncodingFailedDescription() {
        let error = WspulseError.encodingFailed
        XCTAssertEqual(error.description, "wspulse: codec produced non-UTF8 data for text frame")
    }

    // MARK: - All descriptions start with wspulse prefix

    func testAllDescriptionsHavePrefix() {
        let allCases: [WspulseError] = [
            .connectionClosed, .sendBufferFull, .retriesExhausted,
            .connectionLost, .encodingFailed,
        ]
        for error in allCases {
            XCTAssertTrue(
                error.description.hasPrefix("wspulse:"),
                "\(error) description missing 'wspulse:' prefix: \(error.description)"
            )
        }
    }

    // MARK: - LocalizedError conformance

    func testErrorDescriptionMatchesDescription() {
        let allCases: [WspulseError] = [
            .connectionClosed, .sendBufferFull, .retriesExhausted,
            .connectionLost, .encodingFailed,
        ]
        for error in allCases {
            XCTAssertEqual(error.errorDescription, error.description)
        }
    }

    // MARK: - Equatable conformance

    func testEquality() {
        XCTAssertEqual(WspulseError.connectionClosed, WspulseError.connectionClosed)
        XCTAssertEqual(WspulseError.sendBufferFull, WspulseError.sendBufferFull)
        XCTAssertEqual(WspulseError.retriesExhausted, WspulseError.retriesExhausted)
        XCTAssertEqual(WspulseError.connectionLost, WspulseError.connectionLost)
        XCTAssertEqual(WspulseError.encodingFailed, WspulseError.encodingFailed)
    }

    func testInequality() {
        XCTAssertNotEqual(WspulseError.connectionClosed, WspulseError.sendBufferFull)
        XCTAssertNotEqual(WspulseError.retriesExhausted, WspulseError.connectionLost)
        XCTAssertNotEqual(WspulseError.encodingFailed, WspulseError.connectionClosed)
    }

    // MARK: - Error conformance

    func testCanBeCaughtAsError() {
        func throwError() throws {
            throw WspulseError.connectionClosed
        }
        XCTAssertThrowsError(try throwError()) { error in
            XCTAssertTrue(error is WspulseError)
            XCTAssertEqual(error as? WspulseError, .connectionClosed)
        }
    }

    func testLocalizedDescriptionIsNotEmpty() {
        let allCases: [WspulseError] = [
            .connectionClosed, .sendBufferFull, .retriesExhausted,
            .connectionLost, .encodingFailed,
        ]
        for error in allCases {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
