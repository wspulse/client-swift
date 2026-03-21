import WspulseClient
import XCTest

final class OptionsTests: XCTestCase {
    // MARK: - Default values

    func testDefaultOptionsValues() {
        let opts = WspulseClientOptions()
        XCTAssertNil(opts.onMessage)
        XCTAssertNil(opts.onDisconnect)
        XCTAssertNil(opts.onReconnect)
        XCTAssertNil(opts.onTransportDrop)
        XCTAssertNil(opts.autoReconnect)
        XCTAssertEqual(opts.writeWait, .seconds(10))
        XCTAssertEqual(opts.maxMessageSize, 1_048_576)
        XCTAssertTrue(opts.dialHeaders.isEmpty)
        XCTAssertEqual(opts.codec.frameType, .text)
    }

    func testDefaultHeartbeatValues() {
        let heartbeat = HeartbeatOptions()
        XCTAssertEqual(heartbeat.pingPeriod, .seconds(20))
        XCTAssertEqual(heartbeat.pongWait, .seconds(60))
    }

    func testDefaultAutoReconnectValues() {
        let reconnect = AutoReconnectOptions()
        XCTAssertEqual(reconnect.maxRetries, 0)
        XCTAssertEqual(reconnect.baseDelay, .seconds(1))
        XCTAssertEqual(reconnect.maxDelay, .seconds(30))
    }

    // MARK: - Custom values

    func testCustomOptionsValues() {
        let opts = WspulseClientOptions(
            onMessage: { _ in },
            autoReconnect: AutoReconnectOptions(maxRetries: 5, baseDelay: .seconds(2), maxDelay: .seconds(60)),
            heartbeat: HeartbeatOptions(pingPeriod: .seconds(10), pongWait: .seconds(30)),
            writeWait: .seconds(5),
            maxMessageSize: 2_097_152,
            dialHeaders: ["Authorization": "Bearer token"]
        )
        XCTAssertNotNil(opts.onMessage)
        XCTAssertNotNil(opts.autoReconnect)
        XCTAssertEqual(opts.autoReconnect?.maxRetries, 5)
        XCTAssertEqual(opts.autoReconnect?.baseDelay, .seconds(2))
        XCTAssertEqual(opts.autoReconnect?.maxDelay, .seconds(60))
        XCTAssertEqual(opts.heartbeat.pingPeriod, .seconds(10))
        XCTAssertEqual(opts.heartbeat.pongWait, .seconds(30))
        XCTAssertEqual(opts.writeWait, .seconds(5))
        XCTAssertEqual(opts.maxMessageSize, 2_097_152)
        XCTAssertEqual(opts.dialHeaders["Authorization"], "Bearer token")
    }

    // MARK: - Precondition tests (skipped)
    //
    // Precondition failures terminate the process and cannot be caught in Swift.
    // These tests are skipped in-process; valid-boundary tests below verify the
    // non-crash paths. In a CI environment with process-isolation support
    // (e.g. XCTest crash testing plans), these would verify the trap.

    // MARK: - Valid boundary values do not crash

    func testAutoReconnectWithZeroRetriesMeansUnlimited() {
        let reconnect = AutoReconnectOptions(maxRetries: 0)
        XCTAssertEqual(reconnect.maxRetries, 0)
    }

    func testAutoReconnectMaxDelayEqualsBaseDelay() {
        let reconnect = AutoReconnectOptions(baseDelay: .seconds(5), maxDelay: .seconds(5))
        XCTAssertEqual(reconnect.baseDelay, reconnect.maxDelay)
    }

    func testHeartbeatMinimalGap() {
        let heartbeat = HeartbeatOptions(pingPeriod: .milliseconds(1), pongWait: .milliseconds(2))
        XCTAssertEqual(heartbeat.pingPeriod, .milliseconds(1))
        XCTAssertEqual(heartbeat.pongWait, .milliseconds(2))
    }

    func testMaxMessageSizeMinimum() {
        let opts = WspulseClientOptions(maxMessageSize: 1)
        XCTAssertEqual(opts.maxMessageSize, 1)
    }

    // MARK: - Callbacks are invoked

    func testOnMessageCallbackIsInvoked() {
        let expectation = XCTestExpectation(description: "onMessage called")
        let opts = WspulseClientOptions(onMessage: { frame in
            XCTAssertEqual(frame.event, "test")
            expectation.fulfill()
        })
        opts.onMessage?(Frame(event: "test"))
        wait(for: [expectation], timeout: 1)
    }

    func testOnDisconnectCallbackIsInvoked() {
        let expectation = XCTestExpectation(description: "onDisconnect called")
        let opts = WspulseClientOptions(onDisconnect: { error in
            XCTAssertNil(error)
            expectation.fulfill()
        })
        opts.onDisconnect?(nil)
        wait(for: [expectation], timeout: 1)
    }

    func testOnReconnectCallbackIsInvoked() {
        let expectation = XCTestExpectation(description: "onReconnect called")
        let opts = WspulseClientOptions(onReconnect: { attempt in
            XCTAssertEqual(attempt, 3)
            expectation.fulfill()
        })
        opts.onReconnect?(3)
        wait(for: [expectation], timeout: 1)
    }

    func testOnTransportDropCallbackIsInvoked() {
        let expectation = XCTestExpectation(description: "onTransportDrop called")
        let opts = WspulseClientOptions(onTransportDrop: { error in
            XCTAssertTrue(error is WspulseError)
            expectation.fulfill()
        })
        opts.onTransportDrop?(WspulseError.connectionLost)
        wait(for: [expectation], timeout: 1)
    }

}
