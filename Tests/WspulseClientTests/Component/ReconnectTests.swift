import XCTest

@testable import WspulseClient

// MARK: - ReconnectTests

/// Reconnect flow component tests using mock transport.
final class ReconnectTests: XCTestCase {

    // MARK: - Helpers

    private let codec = JSONCodec()

    private func encode(_ frame: Frame) throws -> Data {
        try codec.encode(frame)
    }

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
            domain: "ReconnectTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: msg]
        )
    }

    // MARK: - Auto-reconnect after transport drop

    func testReconnectsAfterTransportDrop() async throws {
        let state = TestState()
        let transport1 = MockTransport()
        let transport2 = MockTransport()
        let sleeper = FakeSleeper()

        let dialer = MockDialerTransport(
            transports: [transport1, transport2]
        )

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) },
                onTransportRestore: {
                    state.addTransportRestore()
                },
                onTransportDrop: { state.addTransportDrop($0) },
                autoReconnect: AutoReconnectOptions(
                    maxRetries: 5,
                    baseDelay: .milliseconds(10),
                    maxDelay: .milliseconds(50)
                )
            ),
            transport: dialer,
            sleeper: sleeper
        )
        try await client.connect()

        let beforeData = try encode(Frame(event: "before"))
        await transport1.injectData(beforeData)
        try await waitUntil { state.receivedCount >= 1 }

        await transport1.injectError(
            NSError(domain: "test", code: 1, userInfo: nil)
        )

        try await waitUntil { state.transportDropCalled }

        // Advance past the reconnect backoff delay.
        await sleeper.advance(count: 1)

        try await waitUntil(timeout: 5) {
            state.transportRestoreCount >= 1
        }

        let afterData = try encode(Frame(event: "after"))
        await transport2.injectData(afterData)

        try await waitUntil { state.receivedCount >= 2 }
        XCTAssertTrue(
            state.received.contains { $0.event == "after" }
        )

        // One transportDrop for the injected error.
        XCTAssertEqual(state.transportDropCount, 1)

        await client.close()

        // close() fires a second onTransportDrop(nil) for the clean shutdown.
        XCTAssertEqual(state.transportDropCount, 2)
    }

    // MARK: - Max retries exhausted

    func testFiresRetriesExhaustedAfterMaxRetries() async throws {
        let state = TestState()
        let transport1 = MockTransport()
        let sleeper = FakeSleeper()

        let dialer = MockDialerTransport(
            transports: [transport1],
            dialErrors: [
                1: NSError(
                    domain: "test", code: 1, userInfo: nil
                ),
                2: NSError(
                    domain: "test", code: 1, userInfo: nil
                ),
            ]
        )

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) },
                onTransportDrop: { state.addTransportDrop($0) },
                autoReconnect: AutoReconnectOptions(
                    maxRetries: 2,
                    baseDelay: .milliseconds(10),
                    maxDelay: .milliseconds(50)
                )
            ),
            transport: dialer,
            sleeper: sleeper
        )
        try await client.connect()

        await transport1.injectError(
            NSError(domain: "test", code: 1, userInfo: nil)
        )

        try await waitUntil { state.transportDropCalled }

        // Advance past 2 sleeps: 1 per retry backoff delay (2 retries).
        await sleeper.advance(count: 2)

        try await waitUntil(timeout: 5) {
            state.disconnectCalled
        }

        if let err = state.firstDisconnectErr as? WspulseError {
            XCTAssertEqual(err, .retriesExhausted)
        } else {
            XCTFail(
                "Expected .retriesExhausted, got "
                    + String(describing: state.firstDisconnectErr)
            )
        }
    }

    // MARK: - close() during reconnect

    func testCloseDuringReconnectFiresDisconnectNil() async throws {
        let state = TestState()
        let transport1 = MockTransport()
        let clientRef = Ref<WspulseClient>()

        let dialer = MockDialerTransport(
            transports: [transport1],
            dialErrors: [
                1: NSError(
                    domain: "test", code: 1, userInfo: nil
                ),
                2: NSError(
                    domain: "test", code: 1, userInfo: nil
                ),
                3: NSError(
                    domain: "test", code: 1, userInfo: nil
                ),
            ]
        )

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) },
                onTransportDrop: { _ in
                    Task {
                        try? await Task.sleep(
                            for: .milliseconds(50)
                        )
                        await clientRef.value?.close()
                    }
                },
                autoReconnect: AutoReconnectOptions(
                    maxRetries: 10,
                    baseDelay: .milliseconds(50),
                    maxDelay: .milliseconds(200)
                )
            ),
            transport: dialer
        )
        clientRef.value = client
        try await client.connect()

        await transport1.injectError(
            NSError(domain: "test", code: 1, userInfo: nil)
        )

        try await waitUntil(timeout: 10) {
            state.disconnectCalled
        }

        XCTAssertEqual(state.disconnectCount, 1)
        XCTAssertNil(state.firstDisconnectErr)
    }
}
