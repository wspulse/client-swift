import Foundation

@testable import WspulseClient

/// Mock transport actor for component tests.
/// Channel-based, deterministic, zero network I/O.
actor MockTransport: TransportProtocol {
    private var receiveQueue: [Result<Data, Error>] = []
    private var receiveContinuations: [CheckedContinuation<Data, Error>] = []
    private(set) var sentData: [Data] = []
    private(set) var dialCount = 0
    private var closed = false
    private var dialError: Error?
    private var dialSuspended = false
    private var dialContinuation: CheckedContinuation<Void, Error>?
    private var sendError: Error?

    func dial(url: URL, headers: [String: String]) async throws {
        dialCount += 1
        if let error = dialError {
            throw error
        }
        if dialSuspended {
            try await withCheckedThrowingContinuation { cont in
                precondition(
                    dialContinuation == nil,
                    "wspulse: MockTransport already has a suspended dial — call resumeDial() or failDial() first"
                )
                dialContinuation = cont
            }
        }
        closed = false
    }

    func send(_ data: Data, frameType: FrameType) async throws {
        guard !closed else { throw WspulseError.connectionClosed }
        if let error = sendError {
            throw error
        }
        sentData.append(data)
    }

    func receive() async throws -> Data {
        if !receiveQueue.isEmpty {
            let next = receiveQueue.removeFirst()
            return try next.get()
        }
        return try await withCheckedThrowingContinuation { cont in
            if closed {
                cont.resume(throwing: WspulseError.connectionClosed)
            } else {
                receiveContinuations.append(cont)
            }
        }
    }

    func close() {
        closed = true
        failPendingReceives()
        failPendingDial()
    }

    func close(code: URLSessionWebSocketTask.CloseCode) {
        close()
    }

    // MARK: - Test helpers

    /// Inject a text message into the receive queue.
    func injectMessage(_ string: String) {
        let data = Data(string.utf8)
        if !receiveContinuations.isEmpty {
            let cont = receiveContinuations.removeFirst()
            cont.resume(returning: data)
        } else {
            receiveQueue.append(.success(data))
        }
    }

    /// Inject raw data into the receive queue.
    func injectData(_ data: Data) {
        if !receiveContinuations.isEmpty {
            let cont = receiveContinuations.removeFirst()
            cont.resume(returning: data)
        } else {
            receiveQueue.append(.success(data))
        }
    }

    /// Inject an error into the receive queue (simulates transport drop).
    func injectError(_ error: Error) {
        if !receiveContinuations.isEmpty {
            let cont = receiveContinuations.removeFirst()
            cont.resume(throwing: error)
        } else {
            receiveQueue.append(.failure(error))
        }
    }

    /// Configure send() to throw an error (without closing transport).
    func setSendError(_ error: Error?) {
        sendError = error
    }

    /// Configure dial to throw an error.
    func setDialError(_ error: Error?) {
        dialError = error
    }

    /// Make dial() suspend until resumeDial() or failDial() is called.
    func setDialSuspended(_ suspended: Bool = true) {
        dialSuspended = suspended
    }

    /// Resume a suspended dial() call with success.
    func resumeDial() {
        let cont = dialContinuation
        dialContinuation = nil
        cont?.resume()
    }

    /// Resume a suspended dial() call with an error.
    func failDial(with error: Error) {
        let cont = dialContinuation
        dialContinuation = nil
        cont?.resume(throwing: error)
    }

    /// Reset closed state (for reuse after close).
    func reset() {
        failPendingReceives()
        failPendingDial()
        closed = false
        sentData.removeAll()
        receiveQueue.removeAll()
        dialCount = 0
        dialError = nil
        dialSuspended = false
        sendError = nil
    }

    /// Whether the transport is currently closed.
    var isClosed: Bool { closed }

    /// Number of pending receive continuations.
    var pendingReceiveCount: Int { receiveContinuations.count }

    private func failPendingReceives() {
        let pending = receiveContinuations
        receiveContinuations.removeAll()
        for cont in pending {
            cont.resume(throwing: WspulseError.connectionClosed)
        }
    }

    private func failPendingDial() {
        let cont = dialContinuation
        dialContinuation = nil
        cont?.resume(throwing: WspulseError.connectionClosed)
    }
}

/// Mock dialer transport that sequences multiple transports for reconnect tests.
///
/// Each `dial()` call advances to the next transport in the sequence.
/// The current transport's `send`, `receive`, and `close`
/// methods are forwarded to the active transport.
actor MockDialerTransport: TransportProtocol {
    private var transports: [MockTransport]
    private var currentIndex = -1
    private var current: MockTransport?
    private var dialErrors: [Int: Error]
    private var closed = false
    private(set) var dialCount = 0

    init(
        transports: [MockTransport],
        dialErrors: [Int: Error] = [:]
    ) {
        self.transports = transports
        self.dialErrors = dialErrors
    }

    func dial(url: URL, headers: [String: String]) async throws {
        let index = dialCount
        dialCount += 1
        if let error = dialErrors[index] {
            throw error
        }
        currentIndex = index
        guard index < transports.count else {
            throw WspulseError.connectionClosed
        }
        current = transports[index]
        try await current!.dial(url: url, headers: headers)
        closed = false
    }

    func send(_ data: Data, frameType: FrameType) async throws {
        guard let current else {
            throw WspulseError.connectionClosed
        }
        try await current.send(data, frameType: frameType)
    }

    func receive() async throws -> Data {
        guard !closed else { throw WspulseError.connectionClosed }
        guard let current else {
            throw WspulseError.connectionClosed
        }
        return try await current.receive()
    }

    func close() {
        closed = true
        let transport = current
        if let transport {
            Task { await transport.close() }
        }
    }

    func close(code: URLSessionWebSocketTask.CloseCode) {
        closed = true
        let transport = current
        if let transport {
            Task { await transport.close() }
        }
    }

    /// Access the current active transport (for injecting messages).
    func currentTransport() -> MockTransport? { current }

    /// Access a transport by index.
    func transport(at index: Int) -> MockTransport {
        transports[index]
    }
}
