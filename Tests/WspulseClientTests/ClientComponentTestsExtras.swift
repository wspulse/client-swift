@testable import WspulseClient
import XCTest

// MARK: - ClientComponentTestsExtras

/// Additional component tests beyond the core 9 scenarios.
final class ClientComponentTestsExtras: XCTestCase {

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

    // MARK: - Frame field round-trip

    func testRoundTripsAllFrameFields() async throws {
        let state = TestState()
        let transport = MockTransport()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) }
            ),
            transport: transport
        )
        try await client.connect()

        let outbound = Frame(
            event: "chat.message",
            payload: .object([
                "user": .string("alice"),
                "text": .string("hi"),
                "n": .number(42),
                "nested": .object(["ok": .bool(true)]),
            ])
        )

        let echoData = try encode(outbound)
        await transport.injectData(echoData)

        try await waitUntil { state.receivedCount >= 1 }
        XCTAssertEqual(state.received.first, outbound)

        await client.close()
    }

    // MARK: - Server rejection (dial throws)

    func testHandlesDialRejectionGracefully() async throws {
        let transport = MockTransport()
        await transport.setDialError(
            NSError(
                domain: "test", code: 403,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "HTTP 403 Forbidden"
                ]
            )
        )

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(),
            transport: transport
        )
        do {
            try await client.connect()
            XCTFail("Expected connect() to throw")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    // MARK: - Message ordering

    func testReceivesFramesInOrder() async throws {
        let count = 10
        let state = TestState()
        let transport = MockTransport()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) }
            ),
            transport: transport
        )
        try await client.connect()

        for idx in 0..<count {
            let frame = Frame(
                event: "seq",
                payload: .object(["i": .number(Double(idx))])
            )
            let data = try encode(frame)
            await transport.injectData(data)
        }

        try await waitUntil(timeout: 10) {
            state.receivedCount >= count
        }
        for idx in 0..<count {
            XCTAssertEqual(state.received[idx].event, "seq")
            XCTAssertEqual(
                state.received[idx].payload,
                .object(["i": .number(Double(idx))])
            )
        }

        await client.close()
    }

    // MARK: - Connect with query params

    func testConnectsWithQueryParams() async throws {
        let state = TestState()
        let transport = MockTransport()

        let client = WspulseClient(
            url: URL(
                string: "ws://127.0.0.1:9999?room=swift-room"
            )!,
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) }
            ),
            transport: transport
        )
        try await client.connect()

        let frame = Frame(
            event: "ping", payload: .string("pong")
        )
        let data = try encode(frame)
        await transport.injectData(data)

        try await waitUntil { state.receivedCount >= 1 }
        XCTAssertEqual(state.received.first?.event, "ping")
        XCTAssertEqual(
            state.received.first?.payload, .string("pong")
        )

        await client.close()
    }

    // MARK: - onDisconnect fires exactly once

    func testOnDisconnectFiresExactlyOnceOnClose(
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

        await client.close()
        for await _ in client.done {}
        XCTAssertEqual(state.disconnectCount, 1)
        XCTAssertNil(state.firstDisconnectErr)
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

    // MARK: - Transport drop fires onDisconnect

    func testTransportDropFiresOnDisconnect() async throws {
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

        await transport.injectError(
            NSError(domain: "test", code: 1, userInfo: nil)
        )
        try await waitUntil(timeout: 10) {
            state.disconnectCalled
        }
        XCTAssertTrue(state.disconnectCalled)
        XCTAssertNotNil(state.firstDisconnectErr)
    }

    // MARK: - onTransportRestore not on initial connect

    func testTransportRestoreNotOnInitialConnect(
    ) async throws {
        let state = TestState()
        let transport = MockTransport()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onTransportRestore: {
                    state.addTransportRestore()
                },
                autoReconnect: AutoReconnectOptions(
                    maxRetries: 3,
                    baseDelay: .milliseconds(10),
                    maxDelay: .milliseconds(50)
                )
            ),
            transport: transport
        )
        try await client.connect()

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(state.transportRestoreCount, 0)

        await client.close()
    }
}
