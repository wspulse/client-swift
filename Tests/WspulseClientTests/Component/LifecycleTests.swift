@testable import WspulseClient
import XCTest

// MARK: - LifecycleTests

/// Client lifecycle component tests using mock transport.
final class LifecycleTests: XCTestCase {

    // MARK: - Helpers

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping @Sendable () -> Bool
    ) async throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        let msg = "waitUntil timed out after \(timeout)s"
        XCTFail(msg)
        throw NSError(
            domain: "LifecycleTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: msg]
        )
    }

    // MARK: - send() after close throws

    func testSendAfterCloseThrowsConnectionClosed(
    ) async throws {
        let transport = MockTransport()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(),
            transport: transport
        )
        try await client.connect()
        await client.close()

        do {
            try await client.send(Frame(event: "msg"))
            XCTFail("Expected WspulseError.connectionClosed")
        } catch let err as WspulseError {
            XCTAssertEqual(err, .connectionClosed)
        }
    }

    // MARK: - Close idempotency

    func testCloseIsIdempotent() async throws {
        let state = TestState()
        let transport = MockTransport()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) }
            ),
            transport: transport
        )
        try await client.connect()

        await client.close()
        await client.close()
        await client.close()
        for await _ in client.done {}
        XCTAssertEqual(state.disconnectCount, 1)
    }

    // MARK: - close() racing with transport drop

    func testCloseRacingWithTransportDropFiresDisconnectOnce(
    ) async throws {
        let state = TestState()
        let transport = MockTransport()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) }
            ),
            transport: transport
        )
        try await client.connect()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await transport.injectError(
                    NSError(
                        domain: "test",
                        code: 1,
                        userInfo: nil
                    )
                )
            }
            group.addTask {
                await client.close()
            }
        }

        try await waitUntil(timeout: 5) {
            state.disconnectCalled
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(state.disconnectCount, 1)
    }
}
