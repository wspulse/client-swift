import Foundation
import WspulseClient
import XCTest

// MARK: - Thread-safe test helpers

/// Thread-safe state collector for integration test callbacks.
final class TestState: @unchecked Sendable {
    private let lock = NSLock()
    private var _received: [Frame] = []
    private var _disconnects: [Error?] = []
    private var _transportDrops: [Error] = []
    private var _reconnects: [Int] = []

    func addReceived(_ frame: Frame)    { lock.withLock { _received.append(frame) } }
    func addDisconnect(_ err: Error?)   { lock.withLock { _disconnects.append(err) } }
    func addTransportDrop(_ err: Error) { lock.withLock { _transportDrops.append(err) } }
    func addReconnect(_ attempt: Int)   { lock.withLock { _reconnects.append(attempt) } }

    var received: [Frame]         { lock.withLock { _received } }
    var receivedCount: Int        { lock.withLock { _received.count } }
    var disconnectCount: Int      { lock.withLock { _disconnects.count } }
    var reconnectCount: Int       { lock.withLock { _reconnects.count } }
    var disconnectCalled: Bool    { lock.withLock { !_disconnects.isEmpty } }
    var transportDropCalled: Bool { lock.withLock { !_transportDrops.isEmpty } }

    /// The error value from the first `onDisconnect` call. `nil` means clean close.
    var firstDisconnectErr: Error? {
        lock.withLock { _disconnects.first.flatMap { $0 } }
    }
}

/// Reference box for capturing a value in a `@Sendable` closure.
final class Ref<T>: @unchecked Sendable {
    var value: T?
    init(_ val: T? = nil) { value = val }
}

// MARK: - ClientIntegrationTests + server lifecycle

private enum TestServerError: Error {
    case notFound
    case buildFailed(String)
    case startFailed
    case timeout
}

extension ClientIntegrationTests {
    // ── Build step ───────────────────────────────────────────────────────────

    static func buildTestserverBinary(in dir: URL, named name: String) throws {
        let proc = Process()
        proc.currentDirectoryURL = dir
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["go", "build", "-o", name, "."]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TestServerError.buildFailed(msg)
        }
    }

    // ── Launch + wait for READY ──────────────────────────────────────────────

    static func launchProcessAndWaitReady(
        _ proc: Process,
        stderrPipe: Pipe
    ) throws -> (wsPort: Int, controlPort: Int) {
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
                for line in lines.dropLast() where line.hasPrefix("READY:") {
                    let rest = line.dropFirst("READY:".count).trimmingCharacters(in: .whitespaces)
                    let parts = rest.split(separator: ":")
                    if parts.count == 2,
                       let wsPort = Int(parts[0]),
                       let ctl = Int(parts[1]) {
                        ready.wsPort = wsPort
                        ready.controlPort = ctl
                        sem.signal()
                        return
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
        return (wsPort: ready.wsPort, controlPort: ready.controlPort)
    }

    // ── Testserver startup ────────────────────────────────────────────────────

    static func startTestServer() throws {
        let testserverDir = try findTestserverDir()
        let binaryName = "testserver"
        try buildTestserverBinary(in: testserverDir, named: binaryName)

        let proc = Process()
        proc.currentDirectoryURL = testserverDir
        proc.executableURL = testserverDir.appendingPathComponent(binaryName)
        let stderrPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = stderrPipe
        try proc.run()

        let ports = try launchProcessAndWaitReady(proc, stderrPipe: stderrPipe)
        serverProcess = proc
        serverUrl = "ws://127.0.0.1:\(ports.wsPort)"
        controlUrl = "http://127.0.0.1:\(ports.controlPort)"
    }

    // ── Directory search ──────────────────────────────────────────────────────

    static func findTestserverDir() throws -> URL {
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
}
