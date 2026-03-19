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
    private var connected = false
    private var sendBuffer: [Data] = []
    private let sendBufferMax = 256

    // Signal channel for the write loop: each element means "there's data to send".
    private let writeSignal: AsyncStream<Void>
    private let writeSignalContinuation: AsyncStream<Void>.Continuation

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
    /// Throws if the initial connection fails and auto-reconnect is disabled.
    public func connect() async throws {
        guard !closed else { throw WspulseError.connectionClosed }

        await connection.dial(url: url, headers: options.dialHeaders)
        connected = true

        startReadLoop()
        startWriteLoop()
        startPingLoop()
    }

    /// Enqueue a frame for delivery.
    ///
    /// - Throws: ``WspulseError/connectionClosed`` if the client is closed.
    /// - Throws: ``WspulseError/sendBufferFull`` if the buffer is full.
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
        connected = false

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
        writeTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.writeSignal {
                if Task.isCancelled { return }
                await self.drainBuffer()
            }
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

    private func handleTransportDrop(error: Error) {
        guard !closed else { return }
        connected = false

        // Stop current loops
        readTask?.cancel()
        writeTask?.cancel()
        pingTask?.cancel()

        options.onTransportDrop?(error)

        guard options.autoReconnect != nil else {
            // No auto-reconnect: permanent disconnect
            closed = true
            options.onDisconnect?(WspulseError.connectionLost)
            doneContinuation.yield()
            doneContinuation.finish()
            return
        }

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

                await self.connection.close()
                await self.connection.dial(url: self.url, headers: self.options.dialHeaders)

                // Test the connection by trying to receive or send
                do {
                    // Try a ping to verify connection is alive
                    try await self.connection.sendPing()

                    // Success — restart loops
                    await self.reconnected()
                    return
                } catch {
                    attempt += 1
                    if reconnectOptions.maxRetries > 0 && attempt >= reconnectOptions.maxRetries {
                        await self.reconnectExhausted()
                        return
                    }
                }
            }
        }
    }

    private func reconnected() {
        connected = true
        startReadLoop()
        startWriteLoop()
        startPingLoop()
        // Flush any buffered messages
        writeSignalContinuation.yield()
    }

    private func notifyReconnect(attempt: Int) {
        options.onReconnect?(attempt)
    }

    private func reconnectExhausted() {
        guard !closed else { return }
        closed = true
        connected = false
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
        while !sendBuffer.isEmpty {
            let data = sendBuffer.removeFirst()
            do {
                try await connection.send(data, frameType: options.codec.frameType)
            } catch {
                if closed { return }
                // Re-insert at front if send failed (will retry after reconnect)
                sendBuffer.insert(data, at: 0)
                return
            }
        }
    }
}
