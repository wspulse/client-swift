import Foundation
import os
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

    let url: URL
    let options: WspulseClientOptions
    let connection: ConnectionActor
    let doneContinuation: AsyncStream<Void>.Continuation

    var closed = false
    var started = false
    /// Prevents duplicate ``handleTransportDrop`` calls while the reconnect
    /// loop is active (e.g. when both the read loop and ping loop detect the
    /// same transport drop).
    var reconnecting = false
    var sendBuffer: [Data] = []
    let sendBufferMax: Int

    // Signal channel for the write loop: each element means "there's data to send".
    // Declared `var` so startWriteLoop() can replace the stream on each connection
    // cycle — AsyncStream supports only one active iterator.
    var writeSignal: AsyncStream<Void>
    var writeSignalContinuation: AsyncStream<Void>.Continuation

    // Internal tasks
    var readTask: Task<Void, Never>?
    var writeTask: Task<Void, Never>?
    var reconnectTask: Task<Void, Never>?
    var pingTask: Task<Void, Never>?

    public init(url: URL, options: WspulseClientOptions = WspulseClientOptions()) {
        self.url = url
        self.options = options
        self.sendBufferMax = options.sendBufferSize
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
    /// Throws if the WebSocket handshake fails (e.g. HTTP 403), regardless
    /// of whether auto-reconnect is enabled. Auto-reconnect only activates
    /// after a successful initial connection — initial failures typically
    /// indicate configuration errors that retries cannot fix.
    ///
    /// Idempotent: calling after the connection is already established is a no-op.
    ///
    /// - Throws: ``WspulseError/connectionClosed`` if the client has been permanently closed.
    /// - Throws: The underlying handshake error if the initial dial fails.
    public func connect() async throws {
        guard !closed else { throw WspulseError.connectionClosed }
        guard !started else { return }
        started = true

        do {
            try await connection.dial(url: url, headers: options.dialHeaders)
        } catch {
            options.logger.warning("wspulse/client: initial dial failed: \(error)")
            await connection.close()
            closed = true
            doneContinuation.yield()
            doneContinuation.finish()
            throw error
        }

        options.logger.debug("wspulse/client: connected url=\(self.url)")
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

        options.logger.info("wspulse/client: closing url=\(self.url)")

        // Only fire onDisconnect if the client was previously connected.
        // Per the behaviour contract, no callbacks fire if connect() was
        // never called or if the initial dial failed.
        if started {
            options.onDisconnect?(nil)
        }
        doneContinuation.yield()
        doneContinuation.finish()
    }
}
