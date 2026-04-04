@testable import WspulseClient
import XCTest

// MARK: - CallbackTests

/// Callback behavior component tests using mock transport.
final class CallbackTests: XCTestCase {

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
            domain: "CallbackTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: msg]
        )
    }

    // MARK: - Transport error fires callbacks (no reconnect)

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

    // MARK: - onDisconnect fires exactly once on close

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

        XCTAssertEqual(state.transportRestoreCount, 0)

        await client.close()
    }

    // MARK: - Clean close fires onTransportDrop(nil) before onDisconnect(nil)

    func testCleanCloseFiresTransportDropNilBeforeDisconnect(
    ) async throws {
        let order = OrderTracker()
        let transport = MockTransport()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onDisconnect: { _ in order.record("disconnect") },
                onTransportDrop: { err in
                    XCTAssertNil(err, "onTransportDrop should receive nil on clean close")
                    order.record("transportDrop")
                }
            ),
            transport: transport
        )
        try await client.connect()

        await client.close()
        for await _ in client.done {}

        XCTAssertEqual(
            order.events,
            ["transportDrop", "disconnect"],
            "onTransportDrop(nil) must fire before onDisconnect(nil)"
        )
    }
}
