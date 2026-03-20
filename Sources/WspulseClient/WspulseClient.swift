import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A WebSocket client with optional automatic reconnection.
///
/// All public methods are actor-isolated, ensuring thread safety.
/// Use ``connect()`` to establish the connection, ``send(_:)`` to enqueue
/// frames, and ``close()`` to permanently terminate.
public actor WspulseClient {
    /// Yields once and finishes when the client is permanently disconnected.
    nonisolated public let done: AsyncStream<Void>

    private let url: URL
    private let options: WspulseClientOptions
    private let connection: ConnectionActor
    private let doneContinuation: AsyncStream<Void>.Continuation

    private var closed = false
    private var started = false
    /// Prevents duplicate ``handleTransportDrop`` calls while the reconnect
    /// loop is active (e.g. when both the read loop and ping loop detect the
    /// same transport drop).
    private var reconnecting = false
    private var sendBuffer: [Data] = []
    private let sendBufferMax = 256

    // Signal channel for the write loop: each element means "there's data to send".
    // Declared `var` so startWriteLoop() can replace the stream on each connection
    // cycle — AsyncStream supports only one active iterator.
    private var writeSignal: AsyncStream<Void>
    private var writeSignalContinuation: AsyncStream<Void>.Continuation

    // Internal tasks
    private var readTask: Task<Void, Never>?
    private var writeTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    public init(url: URL, options: WspulseClientOptions = WspulseClientOptions()) {
        self.url = url
        self.options = options
        self.connection = ConnectionActor(maxMessageSize: options.maxMessageSize)

        var cont: AsyncStream<Void>.Continuation!
        self.done = AsyncStream<Void> { cont = $0 }
        self.doneContinuation = cont

        var writeCont: AsyncStream<Void>.Continuation!
        self.writeSignal = AsyncStream<Void> { writeCont = $0 }
        self.writeSignalContinuation = writeCont
    }

    deinit {
        doneContinuation.finish()
        writeSignalContinuation.finish()
    }

    // MARK: - Public API

    /// Establish the WebSocket connection.
    ///
    /// Idempotent: calling after the connection is already established is a no-op.
    ///
    /// - Throws: ``WspulseError/connectionClosed`` if the client has been permanently closed.
    public func connect() async throws {
        guard !closed else { throw WspulseError.connectionClosed }
        guard !started else { return }
        started = true

        await connection.dial(url: url, headers: options.dialHeaders)

        startReadLoop()
        startWriteLoop()
        startPingLoop()
    }

    /// Enqueue a frame for delivery.
    ///
    /// - Throws: ``WspulseError/connectionClosed`` if the client is closed.
    /// - Throws: ``WspulseError/sendBufferFull`` if the buffer is full.
    /// - Throws: An error from the codec if frame serialization fails.
    public func send(_ frame: Frame) throws {
        guard !closed else { throw WspulseError.connectionClosed }

        let data = try options.codec.encode(frame)

        guard sendBuffer.count < sendBufferMax else {
            throw WspulseError.sendBufferFull
        }

        sendBuffer.append(data)
        writeSignalContinuation.yield()
    }

    /// Permanently terminate the connection and stop any reconnect loop.
    ///
    /// Idempotent: calling more than once is safe.
    public func close() async {
        guard !closed else { return }
        closed = true
        reconnecting = false

        // Cancel all internal tasks
        readTask?.cancel()
        writeTask?.cancel()
        reconnectTask?.cancel()
        pingTask?.cancel()

        writeSignalContinuation.finish()

        await connection.close()

        // Await task completion
        await readTask?.value
        await writeTask?.value
        await reconnectTask?.value
        await pingTask?.value

        readTask = nil
        writeTask = nil
        reconnectTask = nil
        pingTask = nil

        options.onDisconnect?(nil)
        doneContinuation.yield()
        doneContinuation.finish()
    }

    // MARK: - Internal loops

    private func startReadLoop() {
        readTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let data = try await self.connection.receive()
                    let frame = await self.decodeFrame(data)
                    await self.handleMessage(frame)
                } catch {
                    if Task.isCancelled { return }
                    await self.handleTransportDrop(error: error)
                    return
                }
            }
        }
    }

    private func startWriteLoop() {
        // Create a fresh write-signal stream for this connection cycle so the new
        // write task gets its own iterator. AsyncStream supports only one active
        // iterator: if we reused the same stream, the old (cancelled) task's iterator
        // and the new task's iterator would compete and yields would be lost.
        var newCont: AsyncStream<Void>.Continuation!
        let newStream = AsyncStream<Void> { newCont = $0 }
        writeSignal = newStream
        writeSignalContinuation = newCont

        writeTask = Task { [weak self] in
            guard let self else { return }
            // Iterate the captured stream directly to avoid an actor hop inside the
            // loop (var properties require await to access from outside the actor).
            for await _ in newStream {
                if Task.isCancelled { return }
                await self.drainBuffer()
            }
        }

        // If there are messages that were enqueued before this connection cycle
        // completed (e.g. while connect() was still dialing), make sure the new
        // write loop is kicked so it can begin draining the existing buffer.
        if !sendBuffer.isEmpty {
            writeSignalContinuation.yield()
        }
    }

    private func startPingLoop() {
        let pingPeriod = options.heartbeat.pingPeriod
        let pongWait = options.heartbeat.pongWait

        pingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: pingPeriod)
                } catch {
                    return
                }
                if Task.isCancelled { return }

                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await self.connection.sendPing()
                        }
                        group.addTask {
                            try await Task.sleep(for: pongWait)
                            throw WspulseError.connectionLost
                        }
                        // First to complete wins; cancel the other.
                        if let result = try await group.next() {
                            _ = result
                        }
                        group.cancelAll()
                    }
                } catch {
                    if Task.isCancelled { return }
                    await self.handleTransportDrop(error: error)
                    return
                }
            }
        }
    }

    // MARK: - Reconnect

    private func handleTransportDrop(error: Error) async {
        guard !closed, !reconnecting else { return }

        // Stop current loops
        readTask?.cancel()
        writeTask?.cancel()
        pingTask?.cancel()

        options.onTransportDrop?(error)

        guard options.autoReconnect != nil else {
            // No auto-reconnect: permanent disconnect.
            closed = true
            await connection.close()
            options.onDisconnect?(WspulseError.connectionLost)
            doneContinuation.yield()
            doneContinuation.finish()
            return
        }

        reconnecting = true
        startReconnectLoop()
    }

    private func startReconnectLoop() {
        guard let reconnectOptions = options.autoReconnect else { return }

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            var attempt = 0

            while !Task.isCancelled {
                let delay = backoff(
                    attempt: attempt,
                    base: reconnectOptions.baseDelay,
                    max: reconnectOptions.maxDelay
                )

                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }

                if Task.isCancelled { return }

                await self.notifyReconnect(attempt: attempt)

                if Task.isCancelled { return }

                let succeeded = await self.attemptReconnect()

                if Task.isCancelled { return }

                if succeeded {
                    await self.reconnected()
                    return
                }

                attempt += 1
                if reconnectOptions.maxRetries > 0 && attempt >= reconnectOptions.maxRetries {
                    await self.reconnectExhausted()
                    return
                }
            }
        }
    }

    /// Try to establish a new connection and verify it with a ping.
    /// Returns `true` on success, `false` on failure.
    private func attemptReconnect() async -> Bool {
        await connection.close()
        await connection.dial(url: url, headers: options.dialHeaders)
        do {
            try await connection.sendPing()
            return true
        } catch {
            return false
        }
    }

    private func reconnected() {
        reconnecting = false
        startReadLoop()
        startWriteLoop()
        startPingLoop()
        // Flush any buffered messages
        writeSignalContinuation.yield()
    }

    private func notifyReconnect(attempt: Int) {
        options.onReconnect?(attempt)
    }

    private func reconnectExhausted() async {
        guard !closed else { return }
        closed = true
        reconnecting = false
        await connection.close()
        options.onDisconnect?(WspulseError.retriesExhausted)
        doneContinuation.yield()
        doneContinuation.finish()
    }

    // MARK: - Helpers

    private func decodeFrame(_ data: Data) -> Frame {
        // Best-effort decode; if it fails, return an empty frame
        (try? options.codec.decode(data)) ?? Frame()
    }

    private func handleMessage(_ frame: Frame) {
        options.onMessage?(frame)
    }

    private func drainBuffer() async {
        let writeWait = options.writeWait
        while !sendBuffer.isEmpty {
            let data = sendBuffer.removeFirst()
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await self.connection.send(data, frameType: self.options.codec.frameType)
                    }
                    group.addTask {
                        try await Task.sleep(for: writeWait)
                        throw WspulseError.connectionLost
                    }
                    if let result = try await group.next() {
                        _ = result
                    }
                    group.cancelAll()
                }
            } catch {
                if closed { return }
                // Re-insert at front so the frame is retried after reconnect,
                // then trigger the transport-drop flow immediately.
                sendBuffer.insert(data, at: 0)
                await handleTransportDrop(error: error)
                return
            }
        }
    }
}
