@testable import WspulseClient
import XCTest

// MARK: - BasicTests

/// Basic connect/send/receive component tests using mock transport.
final class BasicTests: XCTestCase {

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
            domain: "BasicTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: msg]
        )
    }

    // MARK: - Connect -> send -> receive -> close clean

    func testConnectSendReceiveCloseClean() async throws {
        let state = TestState()
        let transport = MockTransport()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) },
                onDisconnect: { state.addDisconnect($0) },
                onTransportDrop: { state.addTransportDrop($0) }
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
        XCTAssertEqual(state.transportDropCount, 1)
        // Clean close fires onTransportDrop with nil.
        if case .some(.none) = state.firstTransportDropErr {
            // ok — nil error
        } else {
            XCTFail("Expected onTransportDrop to fire with nil on clean close")
        }
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
}
