@testable import WspulseClient
import XCTest

// MARK: - ClientComponentTestsMore

/// Component test scenarios 6-9.
final class ClientComponentTestsMore: XCTestCase {

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

    private func waitForSent(
        _ transport: MockTransport,
        count: Int,
        timeout: TimeInterval = 5
    ) async throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            let current = await transport.sentData.count
            if current >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        let actual = await transport.sentData.count
        XCTFail(
            "waitForSent: expected \(count), got \(actual)"
        )
    }

    // MARK: - 6: send() after close

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

    // MARK: - 7: Pong timeout

    func testPongTimeoutTriggersConnectionLost() async throws {
        let state = TestState()
        let transport = MockTransport()
        await transport.suppressPongs()

        let client = WspulseClient(
            url: URL(string: "ws://127.0.0.1:9999")!,
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) },
                heartbeat: HeartbeatOptions(
                    pingPeriod: .milliseconds(50),
                    pongWait: .milliseconds(200)
                )
            ),
            transport: transport
        )
        try await client.connect()

        try await waitUntil(timeout: 10) {
            state.disconnectCalled
        }

        if let err = state.firstDisconnectErr as? WspulseError {
            XCTAssertEqual(err, .connectionLost)
        } else {
            XCTFail(
                "Expected .connectionLost, got "
                    + String(describing: state.firstDisconnectErr)
            )
        }
    }

    // MARK: - 8: Concurrent sends

    func testConcurrentSendsDoNotRace() async throws {
        let senders = 10
        let msgsPerSender = 10
        let total = senders * msgsPerSender
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

        try await sendConcurrentFrames(
            client: client, senders: senders,
            msgsPerSender: msgsPerSender
        )

        try await waitForSent(transport, count: total)

        let sent = await transport.sentData
        XCTAssertEqual(sent.count, total)

        for data in sent {
            await transport.injectData(data)
        }

        try await waitUntil(timeout: 10) {
            state.receivedCount >= total
        }
        XCTAssertEqual(state.receivedCount, total)
        XCTAssertTrue(
            state.received.allSatisfy {
                $0.event == "concurrent"
            }
        )

        assertPerSenderOrdering(state.received)
        await client.close()
    }

    private func sendConcurrentFrames(
        client: WspulseClient,
        senders: Int,
        msgsPerSender: Int
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { grp in
            for senderIdx in 0..<senders {
                grp.addTask {
                    for msgIdx in 0..<msgsPerSender {
                        try await client.send(Frame(
                            event: "concurrent",
                            payload: .object([
                                "s": .number(Double(senderIdx)),
                                "m": .number(Double(msgIdx)),
                            ])
                        ))
                    }
                }
            }
            try await grp.waitForAll()
        }
    }

    private func assertPerSenderOrdering(_ frames: [Frame]) {
        var lastM = [Int: Int]()
        for frame in frames {
            guard
                let obj = frame.payload?.objectValue,
                let sVal = obj["s"]?.numberValue,
                let mVal = obj["m"]?.numberValue
            else { continue }
            let sid = Int(sVal)
            let mid = Int(mVal)
            if let prev = lastM[sid] {
                XCTAssertGreaterThan(
                    mid, prev,
                    "sender \(sid): m=\(mid) after m=\(prev)"
                )
            }
            lastM[sid] = mid
        }
    }

    // MARK: - 9: close() racing with transport drop

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
