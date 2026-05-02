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
    private var _serverClose: (code: UInt16, reason: String)?

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

    /// Close details reported by `didCloseWith:`, if any.
    ///
    /// This value reflects the `URLSessionWebSocketTask` close code and reason
    /// reported by Foundation and may include synthesized or pseudo close codes
    /// for abnormal termination, so a non-nil value does not necessarily mean a
    /// wire close frame was received from the peer.
    var serverClose: (code: UInt16, reason: String)? {
        lock.withLock { _serverClose }
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
        // swiftlint:disable:next optional_data_string_conversion
        let reasonString = reason.map { String(decoding: $0, as: UTF8.self) } ?? ""
        lock.withLock {
            _serverClose = (code: UInt16(exactly: closeCode.rawValue) ?? UInt16.max, reason: reasonString)
        }
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
actor ConnectionActor: TransportProtocol {
    /// RFC 6455 §7.4.1 pseudo-codes that must not appear on the wire.
    /// They are synthesized by the implementation and do not represent a
    /// real server-sent close frame:
    ///   1006 abnormalClosure — TCP drop without any close handshake
    ///   1015 tlsHandshake   — TLS failure (URLSession-synthesized)
    /// Note: 1005 noStatusReceived is NOT included here — it means a close
    /// frame was received but without a status body, which is a real
    /// server-initiated close and must surface as .serverClosed.
    private static let pseudoCloseCodes: Set<UInt16> = [
        StatusCode.abnormalClosure.rawValue,
        StatusCode.tlsHandshake.rawValue,
    ]

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
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
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

    /// Send data over the WebSocket. Uses text or binary message based on wire type.
    func send(_ data: Data, wireType: WireType) async throws {
        guard let task else {
            throw WspulseError.connectionClosed
        }
        let message: URLSessionWebSocketTask.Message
        switch wireType {
        case .text:
            guard let string = String(data: data, encoding: .utf8) else {
                throw WspulseError.encodingFailed
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
        do {
            let message = try await task.receive()
            switch message {
            case .string(let text):
                return Data(text.utf8)
            case .data(let data):
                return data
            @unknown default:
                throw WspulseError.connectionClosed
            }
        } catch {
            // The delegate's didCloseWith: fires before task.receive() throws
            // (the close handler cancels the task after capturing the frame).
            // If we captured a real server close frame, surface it as
            // .serverClosed so onTransportDrop can distinguish the cause.
            // RFC 6455 §7.4.1 defines two pseudo-codes synthesized when no
            // close frame was received at all:
            //   1006 abnormalClosure  — TCP drop without a close handshake
            //   1015 tlsHandshake     — TLS failure (URLSession-synthesized)
            // 1005 noStatusReceived means a close frame WAS received but
            // contained no status body — still a real server-initiated close.
            if let captured = connectionDelegate?.serverClose,
                !ConnectionActor.pseudoCloseCodes.contains(captured.code)
            {
                throw WspulseError.serverClosed(
                    code: StatusCode(rawValue: captured.code),
                    reason: captured.reason
                )
            }
            throw error
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
