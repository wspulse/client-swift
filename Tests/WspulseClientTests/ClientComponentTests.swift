@testable import WspulseClient
import XCTest

// MARK: - ClientComponentTests

/// Component tests using mock transport — deterministic, zero network I/O.
/// Replaces integration tests that required a live Go testserver.
///
/// Core scenarios (1-5) are here; scenarios 6-9 and additional
/// tests are in `ClientComponentTestsAdditional.swift`.
final class ClientComponentTests: XCTestCase {

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
            domain: "ClientComponentTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: msg]
        )
    }

    // MARK: - 1: Connect -> send -> receive -> close clean

    func testConnectSendReceiveCloseClean() async throws {
        let state = TestState()
        let transport = MockTransport()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) },
                onDisconnect: { state.addDisconnect($0) }
            ),
            transport: transport
        )
        try await client.connect()

        let outbound = Frame(
            event: "msg",
            payload: .object(["text": .string("hello")])
        )
        try await client.send(outbound)

        let echoData = try encode(outbound)
        await transport.injectData(echoData)

        try await waitUntil { state.receivedCount >= 1 }
        XCTAssertEqual(state.received.first?.event, "msg")
        XCTAssertEqual(
            state.received.first?.payload,
            .object(["text": .string("hello")])
        )

        await client.close()
        for await _ in client.done {}
        XCTAssertEqual(state.disconnectCount, 1)
        XCTAssertNil(state.firstDisconnectErr)
    }

    // MARK: - 2: Transport error -> callbacks (no reconnect)

    func testTransportErrorFiresTransportDropAndDisconnect(
    ) async throws {
        let state = TestState()
        let transport = MockTransport()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) },
                onTransportDrop: { state.addTransportDrop($0) }
            ),
            transport: transport
        )
        try await client.connect()

        await transport.injectError(
            NSError(
                domain: "test", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "connection reset"
                ]
            )
        )

        try await waitUntil { state.transportDropCalled }
        try await waitUntil { state.disconnectCalled }
        XCTAssertNotNil(state.firstDisconnectErr)
    }

    // MARK: - 3: Auto-reconnect after transport drop

    func testReconnectsAfterTransportDrop() async throws {
        let state = TestState()
        let transport1 = MockTransport()
        let transport2 = MockTransport()

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
                autoReconnect: AutoReconnectOptions(
                    maxRetries: 5,
                    baseDelay: .milliseconds(10),
                    maxDelay: .milliseconds(50)
                )
            ),
            transport: dialer
        )
        try await client.connect()

        let beforeData = try encode(Frame(event: "before"))
        await transport1.injectData(beforeData)
        try await waitUntil { state.receivedCount >= 1 }

        await transport1.injectError(
            NSError(domain: "test", code: 1, userInfo: nil)
        )

        try await waitUntil(timeout: 10) {
            state.transportRestoreCount >= 1
        }

        let afterData = try encode(Frame(event: "after"))
        await transport2.injectData(afterData)

        try await waitUntil { state.receivedCount >= 2 }
        XCTAssertTrue(
            state.received.contains { $0.event == "after" }
        )

        await client.close()
    }

    // MARK: - 4: Max retries exhausted

    func testFiresRetriesExhaustedAfterMaxRetries() async throws {
        let state = TestState()
        let transport1 = MockTransport()

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
                autoReconnect: AutoReconnectOptions(
                    maxRetries: 2,
                    baseDelay: .milliseconds(10),
                    maxDelay: .milliseconds(50)
                )
            ),
            transport: dialer
        )
        try await client.connect()

        await transport1.injectError(
            NSError(domain: "test", code: 1, userInfo: nil)
        )

        try await waitUntil(timeout: 10) {
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

    // MARK: - 5: close() during reconnect

    func testCloseDuringReconnectFiresDisconnectNil(
    ) async throws {
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
