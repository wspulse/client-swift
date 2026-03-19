import Foundation
import WspulseClient
import XCTest

// MARK: - Thread-safe test helpers

/// Thread-safe state collector for integration test callbacks.
private final class TestState: @unchecked Sendable {
    private let lock = NSLock()
    private var _received: [Frame] = []
    private var _disconnects: [Error?] = []
    private var _transportDrops: [Error] = []
    private var _reconnects: [Int] = []

    func addReceived(_ frame: Frame)    { lock.withLock { _received.append(frame) } }
    func addDisconnect(_ err: Error?)   { lock.withLock { _disconnects.append(err) } }
    func addTransportDrop(_ err: Error) { lock.withLock { _transportDrops.append(err) } }
    func addReconnect(_ attempt: Int)   { lock.withLock { _reconnects.append(attempt) } }

    var received: [Frame]       { lock.withLock { _received } }
    var receivedCount: Int      { lock.withLock { _received.count } }
    var disconnectCount: Int    { lock.withLock { _disconnects.count } }
    var reconnectCount: Int     { lock.withLock { _reconnects.count } }
    var disconnectCalled: Bool  { lock.withLock { !_disconnects.isEmpty } }
    var transportDropCalled: Bool { lock.withLock { !_transportDrops.isEmpty } }

    /// The error value from the first `onDisconnect` call. `nil` means clean close.
    var firstDisconnectErr: Error? {
        lock.withLock { _disconnects.first.flatMap { $0 } }
    }
}

/// Reference box for capturing a value in a `@Sendable` closure.
private final class Ref<T>: @unchecked Sendable {
    var value: T?
    init(_ v: T? = nil) { value = v }
}

private enum TestServerError: Error {
    case notFound
    case buildFailed(String)
    case startFailed
    case timeout
}

// MARK: - ClientTests

/// Integration tests against the shared Go testserver.
///
/// The testserver is built and started once per test class. It emits
/// `READY:<ws_port>:<control_port>` on stderr when ready. All 14 scenarios
/// defined in `doc/integration-tests.md` are covered here.
///
/// Run:  `swift test --filter ClientTests`
/// Or:   `make test-integration`
final class ClientTests: XCTestCase {
    // ── Class-level server ───────────────────────────────────────────────────

    nonisolated(unsafe) private static var serverProcess: Process?
    nonisolated(unsafe) private static var serverUrl: String = ""
    nonisolated(unsafe) private static var controlUrl: String = ""

    override class func setUp() {
        super.setUp()
        do {
            try startTestServer()
        } catch {
            print("⚠️  testserver failed to start: \(error)")
        }
    }

    override class func tearDown() {
        serverProcess?.terminate()
        serverProcess?.waitUntilExit()
        serverProcess = nil
        super.tearDown()
    }

    // ── Per-test teardown ────────────────────────────────────────────────────

    private var testClient: WspulseClient?

    override func tearDown() async throws {
        if let client = testClient {
            await client.close()
            for await _ in client.done {}
            testClient = nil
        }
        try await super.tearDown()
    }

    // ── Test helpers ─────────────────────────────────────────────────────────

    private func wsUrl(_ suffix: String = "") -> URL {
        URL(string: Self.serverUrl + suffix)!
    }

    /// Polls `condition` every 50 ms until it returns `true` or `timeout` elapses.
    private func waitUntil(
        timeout: TimeInterval = 10,
        _ condition: @escaping @Sendable () -> Bool
    ) async throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("waitUntil timed out after \(timeout) s")
    }

    @discardableResult
    private func kick(_ id: String) async throws -> Bool {
        var req = URLRequest(url: URL(string: "\(Self.controlUrl)/kick?id=\(id)")!)
        req.httpMethod = "POST"
        let (_, resp) = try await URLSession.shared.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    private func shutdown() async throws {
        var req = URLRequest(url: URL(string: "\(Self.controlUrl)/shutdown")!)
        req.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: req)
    }

    private func restart() async throws {
        var req = URLRequest(url: URL(string: "\(Self.controlUrl)/restart")!)
        req.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: req)
    }

    // ── Testserver startup ───────────────────────────────────────────────────

    private static func startTestServer() throws {
        let testserverDir = try findTestserverDir()

        // Build the testserver binary from source.
        let binaryName = "testserver"
        let buildProc = Process()
        buildProc.currentDirectoryURL = testserverDir
        buildProc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        buildProc.arguments = ["go", "build", "-o", binaryName, "."]
        let buildErrPipe = Pipe()
        buildProc.standardError = buildErrPipe
        buildProc.standardOutput = Pipe()
        try buildProc.run()
        buildProc.waitUntilExit()
        guard buildProc.terminationStatus == 0 else {
            let msg = String(data: buildErrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TestServerError.buildFailed(msg)
        }

        // Start the testserver process.
        let proc = Process()
        proc.currentDirectoryURL = testserverDir
        proc.executableURL = testserverDir.appendingPathComponent(binaryName)
        let stderrPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = stderrPipe
        try proc.run()

        // Block until "READY:<ws_port>:<control_port>" appears on stderr (max 30 s).
        final class ReadyState: @unchecked Sendable {
            var wsPort = 0
            var controlPort = 0
            var error: Error?
        }
        let ready = ReadyState()
        let sem = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let handle = stderrPipe.fileHandleForReading
            var buffer = ""
            while proc.isRunning {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer += String(data: data, encoding: .utf8) ?? ""
                let lines = buffer.components(separatedBy: "\n")
                for line in lines.dropLast() {
                    if line.hasPrefix("READY:") {
                        let rest = line.dropFirst("READY:".count).trimmingCharacters(in: .whitespaces)
                        let parts = rest.split(separator: ":")
                        if parts.count == 2,
                           let ws = Int(parts[0]),
                           let ctl = Int(parts[1]) {
                            ready.wsPort = ws
                            ready.controlPort = ctl
                            sem.signal()
                            return
                        }
                    }
                }
                buffer = lines.last ?? ""
            }
            ready.error = TestServerError.startFailed
            sem.signal()
        }

        guard sem.wait(timeout: .now() + 30) == .success else {
            proc.terminate()
            throw TestServerError.timeout
        }
        if let err = ready.error {
            proc.terminate()
            throw err
        }

        serverProcess = proc
        serverUrl = "ws://127.0.0.1:\(ready.wsPort)"
        controlUrl = "http://127.0.0.1:\(ready.controlPort)"
    }

    private static func findTestserverDir() throws -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while true {
            let candidate = dir.appendingPathComponent("testserver")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("main.go").path) {
                return candidate
            }
            let parent = dir.deletingLastPathComponent()
            guard parent.path != dir.path else { break }
            dir = parent
        }
        throw TestServerError.notFound
    }

    // ── Scenario 1: connect → send → echo → close clean ─────────────────────

    func testConnectSendEchoCloseClean() async throws {
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl(),
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) },
                onDisconnect: { state.addDisconnect($0) }
            )
        )
        testClient = client
        try await client.connect()

        try await client.send(Frame(event: "msg", payload: .object(["text": .string("hello")])))
        try await waitUntil { state.receivedCount >= 1 }
        XCTAssertEqual(state.received.first?.event, "msg")
        XCTAssertEqual(state.received.first?.payload, .object(["text": .string("hello")]))

        await client.close()
        for await _ in client.done {}
        XCTAssertEqual(state.disconnectCount, 1)
        XCTAssertNil(state.firstDisconnectErr)
    }

    // ── Scenario 2: server drop → onTransportDrop + onDisconnect (no reconnect)

    func testServerDropFiresTransportDropAndDisconnect() async throws {
        let id = "drop-no-reconnect-swift"
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl("?id=\(id)"),
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) },
                onTransportDrop: { state.addTransportDrop($0) }
            )
        )
        testClient = client
        try await client.connect()

        try await kick(id)

        try await waitUntil { state.transportDropCalled }
        try await waitUntil { state.disconnectCalled }
        XCTAssertNotNil(state.firstDisconnectErr)
    }

    // ── Scenario 3: auto-reconnect after kick ────────────────────────────────

    func testReconnectsAfterKickAndResumesEcho() async throws {
        let id = "reconnect-swift"
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl("?id=\(id)"),
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) },
                onReconnect: { state.addReconnect($0) },
                autoReconnect: AutoReconnectOptions(
                    maxRetries: 5,
                    baseDelay: .milliseconds(100),
                    maxDelay: .milliseconds(500)
                )
            )
        )
        testClient = client
        try await client.connect()

        // Verify echo works before kick.
        try await client.send(Frame(event: "before"))
        try await waitUntil { state.receivedCount >= 1 }

        try await kick(id)
        try await waitUntil(timeout: 15) { state.reconnectCount >= 1 }

        // Allow new connection to stabilise.
        try await Task.sleep(for: .milliseconds(500))

        let countBefore = state.receivedCount
        try await client.send(Frame(event: "after"))
        try await waitUntil(timeout: 10) { state.receivedCount > countBefore }
        XCTAssertTrue(state.received.contains { $0.event == "after" })
    }

    // ── Scenario 4: retries exhausted ────────────────────────────────────────

    func testFiresRetriesExhaustedAfterShutdown() async throws {
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl(),
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) },
                autoReconnect: AutoReconnectOptions(
                    maxRetries: 2,
                    baseDelay: .milliseconds(50),
                    maxDelay: .milliseconds(100)
                )
            )
        )
        testClient = client
        try await client.connect()

        try await shutdown()

        var waitError: Error?
        do {
            try await waitUntil(timeout: 15) { state.disconnectCalled }
        } catch {
            waitError = error
        }
        // Always restart the server so subsequent tests can connect.
        try? await restart()

        if let e = waitError { throw e }

        if let wspErr = state.firstDisconnectErr as? WspulseError {
            XCTAssertEqual(wspErr, .retriesExhausted)
        } else {
            XCTFail("Expected WspulseError.retriesExhausted, got \(String(describing: state.firstDisconnectErr))")
        }
    }

    // ── Scenario 5: close() during reconnect fires onDisconnect(nil) ─────────

    func testCloseDuringReconnectFiresDisconnectNil() async throws {
        let id = "close-reconnect-swift"
        let state = TestState()
        let clientRef = Ref<WspulseClient>()
        let client = WspulseClient(
            url: wsUrl("?id=\(id)"),
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) },
                onReconnect: { _ in
                    // Close from inside the reconnect callback.
                    Task { await clientRef.value?.close() }
                },
                autoReconnect: AutoReconnectOptions(
                    maxRetries: 10,
                    baseDelay: .milliseconds(100),
                    maxDelay: .milliseconds(500)
                )
            )
        )
        clientRef.value = client
        testClient = client
        try await client.connect()

        try await kick(id)
        try await waitUntil(timeout: 15) { state.disconnectCalled }

        XCTAssertEqual(state.disconnectCount, 1)
        XCTAssertNil(state.firstDisconnectErr)
    }

    // ── Scenario 6: send after close → connectionClosed ──────────────────────

    func testSendAfterCloseThrowsConnectionClosed() async throws {
        let client = WspulseClient(url: wsUrl())
        testClient = client
        try await client.connect()

        await client.close()

        do {
            try await client.send(Frame(event: "msg"))
            XCTFail("Expected WspulseError.connectionClosed")
        } catch let err as WspulseError {
            XCTAssertEqual(err, .connectionClosed)
        }
    }

    // ── Scenario 7: heartbeat pong timeout → connectionLost ──────────────────

    func testPongTimeoutTriggersConnectionLost() async throws {
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl("?ignore_pings=1"),
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) },
                onDisconnect: { state.addDisconnect($0) },
                heartbeat: HeartbeatOptions(
                    pingPeriod: .milliseconds(100),
                    pongWait: .milliseconds(300)
                )
            )
        )
        testClient = client
        try await client.connect()

        // Verify data channel works before the pong timeout fires.
        try await client.send(Frame(event: "echo"))
        try await waitUntil { state.receivedCount >= 1 }

        try await waitUntil(timeout: 10) { state.disconnectCalled }

        if let wspErr = state.firstDisconnectErr as? WspulseError {
            XCTAssertEqual(wspErr, .connectionLost)
        } else {
            XCTFail("Expected WspulseError.connectionLost, got \(String(describing: state.firstDisconnectErr))")
        }
    }

    // ── Scenario 8: concurrent sends do not race ─────────────────────────────

    func testConcurrentSendsDoNotRace() async throws {
        let senders = 10
        let msgsPerSender = 10
        let total = senders * msgsPerSender
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl(),
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) }
            )
        )
        testClient = client
        try await client.connect()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for s in 0..<senders {
                group.addTask {
                    for m in 0..<msgsPerSender {
                        try await client.send(Frame(
                            event: "concurrent",
                            payload: .object(["s": .number(Double(s)), "m": .number(Double(m))])
                        ))
                    }
                }
            }
            try await group.waitForAll()
        }

        try await waitUntil(timeout: 15) { state.receivedCount >= total }
        XCTAssertEqual(state.receivedCount, total)
        XCTAssertTrue(state.received.allSatisfy { $0.event == "concurrent" })
    }

    // ── Scenario 9: close() racing with transport drop fires onDisconnect once

    func testCloseRacingWithTransportDropFiresDisconnectOnce() async throws {
        let id = "close-race-swift"
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl("?id=\(id)"),
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) }
            )
        )
        testClient = client
        try await client.connect()

        // Fire close() and /kick simultaneously.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await self.kick(id) }
            group.addTask { await client.close() }
        }

        try await waitUntil(timeout: 5) { state.disconnectCalled }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(state.disconnectCount, 1)
    }

    // ── Additional 1: frame field round-trip ─────────────────────────────────

    func testRoundTripsAllFrameFields() async throws {
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl(),
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) }
            )
        )
        testClient = client
        try await client.connect()

        let outbound = Frame(
            id: "test-id-001",
            event: "chat.message",
            payload: .object([
                "user": .string("alice"),
                "text": .string("hi"),
                "n": .number(42),
                "nested": .object(["ok": .bool(true)]),
            ])
        )
        try await client.send(outbound)
        try await waitUntil { state.receivedCount >= 1 }
        XCTAssertEqual(state.received.first, outbound)
    }

    // ── Additional 2: server rejection ───────────────────────────────────────

    func testHandlesServerRejectionGracefully() async throws {
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl("?reject=1"),
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) },
                onTransportDrop: { state.addTransportDrop($0) }
            )
        )
        testClient = client
        try await client.connect()

        // Server returns HTTP 403; the read loop surfaces the error via onDisconnect.
        try await waitUntil(timeout: 10) { state.disconnectCalled }
        XCTAssertTrue(state.disconnectCalled)
    }

    // ── Additional 3: message ordering ───────────────────────────────────────

    func testSendsMultipleFramesAndReceivesThemInOrder() async throws {
        let count = 10
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl(),
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) }
            )
        )
        testClient = client
        try await client.connect()

        for i in 0..<count {
            try await client.send(Frame(event: "seq", payload: .object(["i": .number(Double(i))])))
        }

        try await waitUntil(timeout: 10) { state.receivedCount >= count }
        for i in 0..<count {
            XCTAssertEqual(state.received[i].event, "seq")
            XCTAssertEqual(state.received[i].payload, .object(["i": .number(Double(i))]))
        }
    }

    // ── Additional 4: room routing ────────────────────────────────────────────

    func testConnectsToSpecificRoomViaQueryParam() async throws {
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl("?room=swift-room"),
            options: WspulseClientOptions(
                onMessage: { state.addReceived($0) }
            )
        )
        testClient = client
        try await client.connect()

        try await client.send(Frame(event: "ping", payload: .string("pong")))
        try await waitUntil { state.receivedCount >= 1 }
        XCTAssertEqual(state.received.first?.event, "ping")
        XCTAssertEqual(state.received.first?.payload, .string("pong"))
    }

    // ── Additional 5: server-initiated kick ───────────────────────────────────

    func testDetectsServerInitiatedKickViaControlAPI() async throws {
        let id = "kick-test-swift"
        let state = TestState()
        let client = WspulseClient(
            url: wsUrl("?id=\(id)"),
            options: WspulseClientOptions(
                onDisconnect: { state.addDisconnect($0) }
            )
        )
        testClient = client
        try await client.connect()

        try await kick(id)
        try await waitUntil(timeout: 10) { state.disconnectCalled }
        XCTAssertTrue(state.disconnectCalled)
        XCTAssertNotNil(state.firstDisconnectErr)
    }
}
