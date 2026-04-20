import Foundation
import WspulseClient
import XCTest

// MARK: - Thread-safe test helpers

/// Thread-safe state collector for component test callbacks.
final class TestState: @unchecked Sendable {
    private let lock = NSLock()
    private var _received: [Message] = []
    private var _disconnects: [Error?] = []
    private var _transportDrops: [Error?] = []
    private var _transportRestoreCount = 0

    func addReceived(_ message: Message) { lock.withLock { _received.append(message) } }
    func addDisconnect(_ err: Error?) { lock.withLock { _disconnects.append(err) } }
    func addTransportDrop(_ err: Error?) { lock.withLock { _transportDrops.append(err) } }
    func addTransportRestore() { lock.withLock { _transportRestoreCount += 1 } }

    var received: [Message] { lock.withLock { _received } }
    var receivedCount: Int { lock.withLock { _received.count } }
    var disconnectCount: Int { lock.withLock { _disconnects.count } }
    var transportRestoreCount: Int { lock.withLock { _transportRestoreCount } }
    var disconnectCalled: Bool { lock.withLock { !_disconnects.isEmpty } }
    var transportDropCalled: Bool { lock.withLock { !_transportDrops.isEmpty } }
    var transportDropCount: Int { lock.withLock { _transportDrops.count } }

    /// The error value from the first `onDisconnect` call. `nil` means clean close.
    var firstDisconnectErr: Error? {
        lock.withLock { _disconnects.first.flatMap { $0 } }
    }

    /// The error value from the first `onTransportDrop` call. Returns `.some(nil)` for clean close.
    var firstTransportDropErr: Error?? {
        lock.withLock { _transportDrops.first }
    }
}

/// Thread-safe ordered event recorder for callback ordering assertions.
final class OrderTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []

    func record(_ event: String) { lock.withLock { _events.append(event) } }
    var events: [String] { lock.withLock { _events } }
}

/// Reference box for capturing a value in a `@Sendable` closure.
final class Ref<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T?
    var value: T? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
    init(_ val: T? = nil) { _value = val }
}
