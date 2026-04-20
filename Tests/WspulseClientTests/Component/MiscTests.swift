import XCTest

@testable import WspulseClient

// MARK: - MiscTests

/// Miscellaneous component tests using mock transport.
final class MiscTests: XCTestCase {

    // MARK: - Helpers

    private let codec = JSONCodec()

    private func encode(_ message: Message) throws -> Data {
        try codec.encode(message)
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
            domain: "MiscTests",
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

    // MARK: - Concurrent sends

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

        try await sendConcurrentMessages(
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

    private func sendConcurrentMessages(
        client: WspulseClient,
        senders: Int,
        msgsPerSender: Int
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { grp in
            for senderIdx in 0..<senders {
                grp.addTask {
                    for msgIdx in 0..<msgsPerSender {
                        try await client.send(
                            Message(
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

    private func assertPerSenderOrdering(_ messages: [Message]) {
        var lastM = [Int: Int]()
        for msg in messages {
            guard
                let obj = msg.payload?.objectValue,
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

}
