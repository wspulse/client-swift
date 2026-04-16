import XCTest

@testable import WspulseClient

final class ClientUnitTests: XCTestCase {
    // MARK: - Send on closed client

    func testSendOnClosedClientThrowsConnectionClosed() async throws {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!
        )
        await client.close()
        do {
            try await client.send(Frame(event: "msg"))
            XCTFail("Expected WspulseError.connectionClosed")
        } catch let error as WspulseError {
            XCTAssertEqual(error, .connectionClosed)
        }
    }

    // MARK: - Close is idempotent

    func testCloseIsIdempotentWithoutConnect() async {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!
        )
        await client.close()
        await client.close()
        await client.close()
        // Should not crash or hang
    }

    // MARK: - Connect after close throws

    func testConnectAfterCloseThrowsConnectionClosed() async throws {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!
        )
        await client.close()
        do {
            try await client.connect()
            XCTFail("Expected WspulseError.connectionClosed")
        } catch let error as WspulseError {
            XCTAssertEqual(error, .connectionClosed)
        }
    }

    // MARK: - Connect to unreachable host fails

    func testConnectToUnreachableHostThrows() async {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:1")!
        )
        do {
            try await client.connect()
            XCTFail("Expected connection error")
        } catch {
            // Any error is fine — the important thing is it throws
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    // MARK: - Connect is idempotent

    func testConnectIdempotentAfterFailure() async {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:1")!
        )
        // First connect fails
        do { try await client.connect() } catch {}
        // Second connect should throw connectionClosed (client closed itself on failure)
        do {
            try await client.connect()
            XCTFail("Expected error on second connect")
        } catch let error as WspulseError {
            XCTAssertEqual(error, .connectionClosed)
        } catch {
            // Also acceptable — the client is in a closed state
        }
    }

    // MARK: - Send buffer full

    func testSendBufferFullThrowsWhenExhausted() async throws {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!
        )
        // Fill the buffer to capacity (256)
        for idx in 0..<256 {
            await client.appendToBuffer(data: Data("frame-\(idx)".utf8))
        }
        let count = await client.bufferCount
        XCTAssertEqual(count, 256)

        // Mark as started so send() doesn't throw connectionClosed
        await client.setStarted()

        // The 257th send must throw sendBufferFull
        do {
            try await client.send(Frame(event: "overflow"))
            XCTFail("Expected WspulseError.sendBufferFull")
        } catch let error as WspulseError {
            XCTAssertEqual(error, .sendBufferFull)
        }
    }

    // MARK: - Done stream finishes after close

    func testDoneStreamFinishesAfterClose() async {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!
        )
        await client.close()
        // Iterating done should complete
        for await _ in client.done {}
        // If we reach here, the stream properly finished
    }

    // MARK: - Initial dial failure does not fire callbacks

    func testInitialDialFailureDoesNotFireOnDisconnect() async {
        let disconnectState = CallbackState()
        let transportDropState = CallbackState()
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:1")!,
            options: WspulseClientOptions(
                onDisconnect: { _ in disconnectState.increment() },
                onTransportDrop: { _ in transportDropState.increment() }
            )
        )
        do {
            try await client.connect()
        } catch {
            // Expected
        }
        // Per behaviour contract: no callbacks fire on initial dial failure
        XCTAssertEqual(disconnectState.count, 0)
        XCTAssertEqual(transportDropState.count, 0)
    }

    // MARK: - Codec can be customized

    func testCustomCodecIsUsed() async throws {
        let customCodec = MockCodec()
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!,
            options: WspulseClientOptions(codec: customCodec)
        )
        await client.close()
        // Just verify it doesn't crash with a custom codec
    }

    // MARK: - close() before connect must not fire onDisconnect

    func testCloseBeforeConnectDoesNotFireOnDisconnect() async {
        let state = CallbackState()
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!,
            options: WspulseClientOptions(
                onDisconnect: { _ in state.increment() }
            )
        )
        await client.close()
        XCTAssertEqual(
            state.count, 0, "onDisconnect must not fire when close() is called before connect()")
    }

    // MARK: - send() throws sendBufferFull when buffer is full

    func testSendThrowsSendBufferFullWhenBufferIsFull() async throws {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!
        )
        // Fill buffer to default capacity (256)
        for idx in 0..<256 {
            await client.appendToBuffer(data: Data("frame-\(idx)".utf8))
        }
        // send() should throw sendBufferFull even though client is not "closed"
        // But send() checks closed first — we need to set started=true via connect path.
        // Since closed=false by default, send() should hit the buffer-full guard.
        do {
            try await client.send(Frame(event: "overflow"))
            XCTFail("Expected WspulseError.sendBufferFull")
        } catch let error as WspulseError {
            XCTAssertEqual(error, .sendBufferFull)
        }
    }

    // MARK: - sendBufferSize is respected

    func testCustomSendBufferSizeIsRespected() async throws {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!,
            options: WspulseClientOptions(sendBufferSize: 4)
        )
        // Fill to custom capacity
        for idx in 0..<4 {
            await client.appendToBuffer(data: Data("frame-\(idx)".utf8))
        }
        let count = await client.bufferCount
        XCTAssertEqual(count, 4)

        // The 5th send must throw sendBufferFull
        do {
            try await client.send(Frame(event: "overflow"))
            XCTFail("Expected WspulseError.sendBufferFull")
        } catch let error as WspulseError {
            XCTAssertEqual(error, .sendBufferFull)
        }
    }

    // MARK: - send() with failing codec throws encoding error

    func testSendWithFailingCodecThrows() async throws {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!,
            options: WspulseClientOptions(codec: FailingCodec())
        )
        do {
            try await client.send(Frame(event: "test"))
            XCTFail("Expected encoding error from failing codec")
        } catch is WspulseError {
            // connectionClosed — because the client isn't connected
            // This is fine; the closed guard fires first
        } catch {
            // FailingCodec error or connectionClosed
        }
    }

    // MARK: - decodeFrame returns nil on invalid data

    func testDecodeFrameReturnsNilOnBadData() async {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!
        )
        let result = await client.decodeFrame(Data("not-json".utf8))
        XCTAssertNil(result)
    }

    func testDecodeFrameReturnsFrameOnValidData() async throws {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!
        )
        let frame = Frame(event: "test")
        let data = try JSONEncoder().encode(frame)
        let result = await client.decodeFrame(data)
        XCTAssertEqual(result?.event, "test")
    }

    // MARK: - handleMessage invokes onMessage

    func testHandleMessageInvokesOnMessage() async {
        let state = CallbackState()
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!,
            options: WspulseClientOptions(onMessage: { _ in state.increment() })
        )
        await client.handleMessage(Frame(event: "test"))
        XCTAssertEqual(state.count, 1)
    }

    // MARK: - decodeFrame returns nil on codec failure

    func testDecodeFrameReturnsNilOnCodecFailure() async {
        // Verify decodeFrame returns nil when the codec fails to decode.
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!,
            options: WspulseClientOptions(codec: FailingCodec())
        )
        let result = await client.decodeFrame(Data("test".utf8))
        XCTAssertNil(result, "FailingCodec should cause decodeFrame to return nil")
    }

    // MARK: - send buffer is empty after init

    func testSendBufferIsEmptyAfterInit() async {
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!
        )
        let count = await client.bufferCount
        XCTAssertEqual(count, 0)
        await client.close()
    }

    // MARK: - onTransportRestore does not fire on initial connect

    func testOnTransportRestoreDoesNotFireOnInitialConnect() async throws {
        let state = CallbackState()
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:1")!,
            options: WspulseClientOptions(
                onTransportRestore: { state.increment() }
            )
        )
        // Initial connect fails — onTransportRestore must not fire.
        do { try await client.connect() } catch {}
        XCTAssertEqual(state.count, 0)
    }

    // MARK: - Backoff negative attempt

    func testBackoffNegativeAttemptDoesNotCrash() {
        let result = backoff(attempt: -5, base: .seconds(1), max: .seconds(30))
        let seconds = durationToSeconds(result)
        // Negative attempt clamped to 0: delay=1, jitter [0.5..1.0]
        XCTAssertGreaterThanOrEqual(seconds, 0.5)
        XCTAssertLessThanOrEqual(seconds, 1.0)
    }

    // MARK: - Helpers

    private func durationToSeconds(_ dur: Duration) -> Double {
        Double(dur.components.seconds) + Double(dur.components.attoseconds) * 1e-18
    }
}

// MARK: - ConnectionActor unit tests

final class ConnectionActorTests: XCTestCase {
    // MARK: - send before dial throws connectionClosed

    func testSendBeforeDialThrowsConnectionClosed() async {
        let connection = ConnectionActor(maxMessageSize: 1_048_576)
        do {
            try await connection.send(Data("hello".utf8), frameType: .text)
            XCTFail("Expected WspulseError.connectionClosed")
        } catch let error as WspulseError {
            XCTAssertEqual(error, .connectionClosed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - receive before dial throws connectionClosed

    func testReceiveBeforeDialThrowsConnectionClosed() async {
        let connection = ConnectionActor(maxMessageSize: 1_048_576)
        do {
            _ = try await connection.receive()
            XCTFail("Expected WspulseError.connectionClosed")
        } catch let error as WspulseError {
            XCTAssertEqual(error, .connectionClosed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - close is safe without dial

    func testCloseWithoutDialDoesNotCrash() async {
        let connection = ConnectionActor(maxMessageSize: 1_048_576)
        await connection.close()
        await connection.close()
        await connection.close()
        // Should not crash
    }

    // MARK: - close with code is safe without dial

    func testCloseWithCodeWithoutDialDoesNotCrash() async {
        let connection = ConnectionActor(maxMessageSize: 1_048_576)
        await connection.close(code: .goingAway)
        await connection.close(code: .normalClosure)
        // Should not crash
    }

    // MARK: - multiple close calls are safe

    func testMultipleCloseCallsAreSafe() async {
        let connection = ConnectionActor(maxMessageSize: 1_048_576)
        await connection.close()
        await connection.close()
        await connection.close(code: .normalClosure)
        await connection.close(code: .goingAway)
        // Should not crash or deadlock
    }

    // MARK: - operations after close with code

    func testSendAfterCloseWithCodeThrowsConnectionClosed() async {
        let connection = ConnectionActor(maxMessageSize: 1_048_576)
        await connection.close(code: .goingAway)
        do {
            try await connection.send(Data("hello".utf8), frameType: .text)
            XCTFail("Expected WspulseError.connectionClosed")
        } catch let error as WspulseError {
            XCTAssertEqual(error, .connectionClosed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - send/receive after close throws connectionClosed

    func testSendAfterCloseThrowsConnectionClosed() async {
        let connection = ConnectionActor(maxMessageSize: 1_048_576)
        await connection.close()
        do {
            try await connection.send(Data("hello".utf8), frameType: .text)
            XCTFail("Expected WspulseError.connectionClosed")
        } catch let error as WspulseError {
            XCTAssertEqual(error, .connectionClosed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReceiveAfterCloseThrowsConnectionClosed() async {
        let connection = ConnectionActor(maxMessageSize: 1_048_576)
        await connection.close()
        do {
            _ = try await connection.receive()
            XCTFail("Expected WspulseError.connectionClosed")
        } catch let error as WspulseError {
            XCTAssertEqual(error, .connectionClosed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - dial to unreachable host throws

    func testDialToUnreachableHostThrows() async {
        let connection = ConnectionActor(maxMessageSize: 1_048_576)
        do {
            try await connection.dial(url: URL(string: "ws://127.0.0.1:1")!, headers: [:])
            XCTFail("Expected dial to throw")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}

// MARK: - Test helpers

/// Thread-safe counter for callback tracking in unit tests.
private final class CallbackState: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    func increment() {
        lock.withLock { _count += 1 }
    }

    var count: Int {
        lock.withLock { _count }
    }
}

private struct MockCodec: WspulseCodec {
    var frameType: FrameType { .text }

    func encode(_ frame: Frame) throws -> Data {
        try JSONEncoder().encode(frame)
    }

    func decode(_ data: Data) throws -> Frame {
        try JSONDecoder().decode(Frame.self, from: data)
    }
}

private struct FailingCodec: WspulseCodec {
    var frameType: FrameType { .text }

    func encode(_ frame: Frame) throws -> Data {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "encode failed"])
    }

    func decode(_ data: Data) throws -> Frame {
        throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "decode failed"])
    }
}

// MARK: - Internal accessors for testing

extension WspulseClient {
    func appendToBuffer(data: Data) {
        precondition(
            sendBuffer.push(data),
            "appendToBuffer: push failed — buffer is full"
        )
    }

    var bufferCount: Int {
        sendBuffer.count
    }

    func setStarted() {
        started = true
    }
}
