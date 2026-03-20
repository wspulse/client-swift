import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URLSession delegate that tracks WebSocket lifecycle events.
///
/// Signals handshake completion (open/fail) via `configure(onOpen:onFail:)`,
/// and post-handshake connection drops via `setOnClose(_:)`. Kept alive by
/// `ConnectionActor` to prevent delegate callbacks from firing after the
/// session is released.
private final class ConnectionDelegate: NSObject, URLSessionWebSocketDelegate,
    URLSessionTaskDelegate, @unchecked Sendable
{
    private let lock = NSLock()
    private var handshakeSettled = false
    private var onOpen: (() -> Void)?
    private var onFail: ((Error) -> Void)?
    private var onClose: (() -> Void)?
    private var closeFired = false

    func configure(onOpen: @escaping () -> Void, onFail: @escaping (Error) -> Void) {
        lock.withLock {
            self.onOpen = onOpen
            self.onFail = onFail
        }
    }

    /// Register a handler that fires when the connection drops after a
    /// successful handshake. If the close event already occurred before
    /// the handler is set, the handler is called immediately.
    func setOnClose(_ handler: @escaping () -> Void) {
        let shouldCallNow: Bool = lock.withLock {
            if closeFired {
                return true
            }
            self.onClose = handler
            return false
        }
        if shouldCallNow { handler() }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        settleHandshake { self.onOpen?() }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            settleHandshake { self.onFail?(error) }
        }
        // Task completed — connection dropped.
        fireOnClose()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        fireOnClose()
    }

    private func settleHandshake(block: () -> Void) {
        lock.withLock {
            guard !handshakeSettled else { return }
            handshakeSettled = true
            block()
        }
    }

    private func fireOnClose() {
        let handler: (() -> Void)? = lock.withLock {
            guard !closeFired else { return nil }
            closeFired = true
            let captured = onClose
            onClose = nil
            return captured
        }
        handler?()
    }
}

/// Internal actor wrapping `URLSessionWebSocketTask` for connection management.
actor ConnectionActor {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var connectionDelegate: ConnectionDelegate?
    private let maxMessageSize: Int

    init(maxMessageSize: Int) {
        self.maxMessageSize = maxMessageSize
    }

    /// Open a WebSocket connection to the given URL with optional headers.
    ///
    /// Suspends until the WebSocket upgrade handshake completes. Throws on
    /// handshake failure (e.g. HTTP 403), allowing `connect()` to propagate
    /// the error when auto-reconnect is disabled.
    ///
    /// On success, installs a close-detection handler so that server-initiated
    /// close frames cancel the underlying task, causing `receive()` to throw
    /// and trigger the reconnect/disconnect flow.
    func dial(url: URL, headers: [String: String]) async throws {
        let configuration = URLSessionConfiguration.default
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        let delegate = ConnectionDelegate()
        connectionDelegate = delegate

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let wsTask = session.webSocketTask(with: request)
        wsTask.maximumMessageSize = maxMessageSize
        self.session = session
        self.task = wsTask

        let capturedTask = wsTask
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.configure(
                    onOpen: { continuation.resume() },
                    onFail: { error in continuation.resume(throwing: error) }
                )
                capturedTask.resume()
            }
        } onCancel: {
            capturedTask.cancel(with: .goingAway, reason: nil)
        }

        // Handshake succeeded — install close detection. When the server closes
        // the connection, cancel the task so receive() throws immediately.
        delegate.setOnClose {
            capturedTask.cancel(with: .goingAway, reason: nil)
        }
    }

    /// Send data over the WebSocket. Uses text or binary message based on frame type.
    func send(_ data: Data, frameType: FrameType) async throws {
        guard let task else {
            throw WspulseError.connectionClosed
        }
        let message: URLSessionWebSocketTask.Message
        switch frameType {
        case .text:
            guard let string = String(data: data, encoding: .utf8) else {
                preconditionFailure("wspulse: attempted to send non-UTF8 data as a text WebSocket frame")
            }
            message = .string(string)
        case .binary:
            message = .data(data)
        }
        try await task.send(message)
    }

    /// Receive the next message from the WebSocket.
    func receive() async throws -> Data {
        guard let task else {
            throw WspulseError.connectionClosed
        }
        let message = try await task.receive()
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else {
                throw WspulseError.connectionClosed
            }
            return data
        case .data(let data):
            return data
        @unknown default:
            throw WspulseError.connectionClosed
        }
    }

    /// Send a WebSocket ping and wait for the pong.
    ///
    /// Supports cooperative cancellation: when the calling Task is cancelled,
    /// the underlying `URLSessionWebSocketTask` is cancelled so the pong
    /// callback fires immediately with an error, unblocking the continuation.
    func sendPing() async throws {
        guard let task else {
            throw WspulseError.connectionClosed
        }
        let capturedTask = task
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                capturedTask.sendPing { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } onCancel: {
            capturedTask.cancel(with: .goingAway, reason: nil)
        }
    }

    /// Close the WebSocket connection with a normal closure code.
    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        connectionDelegate = nil
    }

    /// Close with a specific close code (e.g. for protocol errors).
    func close(code: URLSessionWebSocketTask.CloseCode) {
        task?.cancel(with: code, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        connectionDelegate = nil
    }
}
