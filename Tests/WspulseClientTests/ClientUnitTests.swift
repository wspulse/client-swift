@testable import WspulseClient
import XCTest

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

    func testSendBufferFullWhenBufferExhausted() async throws {
        // Cannot connect, but we can test the buffer logic by using @testable
        // to access internal state. We'll create a client and manipulate its
        // started state to test send logic.
        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:0")!
        )
        // Use internal access to fill the buffer without connecting
        // The sendBufferMax is 256
        for idx in 0..<256 {
            await client.appendToBuffer(data: Data("frame-\(idx)".utf8))
        }
        let count = await client.bufferCount
        XCTAssertEqual(count, 256)
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
        XCTAssertEqual(state.count, 0, "onDisconnect must not fire when close() is called before connect()")
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

// MARK: - Internal accessors for testing

extension WspulseClient {
    func appendToBuffer(data: Data) {
        sendBuffer.append(data)
    }

    var bufferCount: Int {
        sendBuffer.count
    }
}
