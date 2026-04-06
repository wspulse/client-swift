import XCTest

@testable import WspulseClient

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

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if await condition() { return }
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

    func testSendAfterCloseThrowsConnectionClosed() async throws {
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

    func testCloseRacingWithTransportDropFiresDisconnectOnce() async throws {
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

    // MARK: - close() during in-flight dial does not fire callbacks

    func testCloseDuringInflightDialDoesNotFireCallbacks() async throws {
        let state = TestState()
        let transport = MockTransport()
        await transport.setDialSuspended()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) },
                onTransportDrop: { state.addTransportDrop($0) }
            ),
            transport: transport
        )

        // Start connect() — it will suspend inside dial().
        let connectTask = Task<Error?, Never> {
            do {
                try await client.connect()
                return nil
            } catch {
                return error
            }
        }

        // Wait until dial is in progress.
        try await waitUntil {
            await transport.dialCount == 1
        }

        // close() while dial is still suspended.
        await client.close()
        for await _ in client.done {}

        // connect() should have thrown connectionClosed because close() ran during dial.
        let connectError = await connectTask.value
        guard let connectError else {
            return XCTFail("connect() should throw WspulseError.connectionClosed")
        }
        guard let wspulseError = connectError as? WspulseError else {
            return XCTFail("connect() should throw WspulseError.connectionClosed, got \(type(of: connectError))")
        }
        XCTAssertEqual(wspulseError, WspulseError.connectionClosed)

        // No callbacks should have fired — no connection was established.
        XCTAssertFalse(
            state.transportDropCalled,
            "onTransportDrop must not fire when close() is called during in-flight dial"
        )
        XCTAssertFalse(
            state.disconnectCalled,
            "onDisconnect must not fire when close() is called during in-flight dial"
        )
    }

    // MARK: - close() during in-flight dial does not start loops

    func testCloseDuringInflightDialDoesNotStartLoops() async throws {
        let state = TestState()
        let transport = MockTransport()
        await transport.setDialSuspended()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) },
                onDisconnect: { state.addDisconnect($0) },
                onTransportDrop: { state.addTransportDrop($0) }
            ),
            transport: transport
        )

        let connectTask = Task<Error?, Never> {
            do {
                try await client.connect()
                return nil
            } catch {
                return error
            }
        }

        try await waitUntil {
            await transport.dialCount == 1
        }

        // Close while dial is still suspended.
        // close() calls connection.close() → failPendingDial(), which resumes
        // the dial continuation with connectionClosed. No manual resumeDial()
        // needed — this is deterministic: connect() always throws without
        // reaching connected=true, so loops are never started.
        await client.close()
        for await _ in client.done {}

        // connect() should have thrown connectionClosed.
        let connectError = await connectTask.value
        guard let connectError else {
            return XCTFail("connect() should throw WspulseError.connectionClosed")
        }
        guard let wspulseError = connectError as? WspulseError else {
            return XCTFail(
                "connect() should throw WspulseError.connectionClosed, got \(type(of: connectError))"
            )
        }
        XCTAssertEqual(wspulseError, WspulseError.connectionClosed)

        // No callbacks should have fired.
        XCTAssertFalse(
            state.transportDropCalled,
            "onTransportDrop must not fire when close() races with in-flight dial"
        )
        XCTAssertFalse(
            state.disconnectCalled,
            "onDisconnect must not fire when close() races with in-flight dial"
        )

        // No messages should have been received (loops not started).
        XCTAssertEqual(state.receivedCount, 0)
    }
}
