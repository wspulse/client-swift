import WspulseClient
import XCTest

final class OptionsTests: XCTestCase {
    // MARK: - Default values

    func testDefaultOptionsValues() {
        let opts = WspulseClientOptions()
        XCTAssertNil(opts.onMessage)
        XCTAssertNil(opts.onDisconnect)
        XCTAssertNil(opts.onTransportRestore)
        XCTAssertNil(opts.onTransportDrop)
        XCTAssertNil(opts.autoReconnect)
        XCTAssertEqual(opts.writeWait, .seconds(10))
        XCTAssertEqual(opts.maxMessageSize, 1_048_576)
        XCTAssertEqual(opts.sendBufferSize, 256)
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
            sendBufferSize: 512,
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
        XCTAssertEqual(opts.sendBufferSize, 512)
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

    func testSendBufferSizeMinimumBoundary() {
        let opts = WspulseClientOptions(sendBufferSize: 1)
        XCTAssertEqual(opts.sendBufferSize, 1)
    }

    func testSendBufferSizeMaximumBoundary() {
        let opts = WspulseClientOptions(sendBufferSize: 4096)
        XCTAssertEqual(opts.sendBufferSize, 4096)
    }

    func testSendBufferSizeCustomValue() {
        let opts = WspulseClientOptions(sendBufferSize: 128)
        XCTAssertEqual(opts.sendBufferSize, 128)
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

    func testOnTransportRestoreCallbackIsInvoked() {
        let expectation = XCTestExpectation(description: "onTransportRestore called")
        let opts = WspulseClientOptions(onTransportRestore: {
            expectation.fulfill()
        })
        opts.onTransportRestore?()
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

    func testOnTransportDropCallbackAcceptsNil() {
        let expectation = XCTestExpectation(description: "onTransportDrop called with nil")
        let opts = WspulseClientOptions(onTransportDrop: { error in
            XCTAssertNil(error)
            expectation.fulfill()
        })
        opts.onTransportDrop?(nil)
        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Max boundary values (should NOT crash)

    func testHeartbeatMaxBoundaryValues() {
        let heartbeat = HeartbeatOptions(pingPeriod: .seconds(60), pongWait: .seconds(120))
        XCTAssertEqual(heartbeat.pingPeriod, .seconds(60))
        XCTAssertEqual(heartbeat.pongWait, .seconds(120))
    }

    func testAutoReconnectMaxBoundaryValues() {
        let reconnect = AutoReconnectOptions(maxRetries: 32, baseDelay: .seconds(60), maxDelay: .seconds(300))
        XCTAssertEqual(reconnect.maxRetries, 32)
        XCTAssertEqual(reconnect.baseDelay, .seconds(60))
        XCTAssertEqual(reconnect.maxDelay, .seconds(300))
    }

    func testWriteWaitMaxBoundary() {
        let opts = WspulseClientOptions(writeWait: .seconds(30))
        XCTAssertEqual(opts.writeWait, .seconds(30))
    }

    func testMaxMessageSizeZeroIsValid() {
        let opts = WspulseClientOptions(maxMessageSize: 0)
        XCTAssertEqual(opts.maxMessageSize, 0)
    }

    func testMaxMessageSizeMaxBoundary() {
        let opts = WspulseClientOptions(maxMessageSize: 64 * 1_048_576)
        XCTAssertEqual(opts.maxMessageSize, 64 * 1_048_576)
    }
}
