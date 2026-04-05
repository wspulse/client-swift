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
    let connection: any TransportProtocol
    let sleeper: any Sleeper
    let randomJitter: @Sendable () -> Double
    let doneContinuation: AsyncStream<Void>.Continuation

    var closed = false
    var started = false
    /// Set to `true` after the first successful `connection.dial()`.
    /// Used by `close()` to decide whether callbacks should fire.
    /// Never reset — once connected, `close()` must fire callbacks
    /// even if the transport is currently down (reconnecting state).
    var connected = false
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
        self.url = Self.normalizeScheme(url)
        self.options = options
        self.sendBufferMax = options.sendBufferSize
        self.connection = ConnectionActor(maxMessageSize: options.maxMessageSize)
        self.sleeper = RealSleeper()
        self.randomJitter = { Double.random(in: 0.5...1.0) }

        var cont: AsyncStream<Void>.Continuation!
        self.done = AsyncStream<Void> { cont = $0 }
        self.doneContinuation = cont

        var writeCont: AsyncStream<Void>.Continuation!
        self.writeSignal = AsyncStream<Void> { writeCont = $0 }
        self.writeSignalContinuation = writeCont
    }

    /// Internal initializer for testing with a custom transport.
    init(
        url: URL,
        options: WspulseClientOptions,
        transport: any TransportProtocol,
        sleeper: any Sleeper = RealSleeper(),
        randomJitter: @escaping @Sendable () -> Double = { Double.random(in: 0.5...1.0) }
    ) {
        self.url = Self.normalizeScheme(url)
        self.options = options
        self.sendBufferMax = options.sendBufferSize
        self.connection = transport
        self.sleeper = sleeper
        self.randomJitter = randomJitter

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
            // If close() already ran during the dial suspension, skip
            // state changes it already performed.
            if !closed {
                closed = true
                doneContinuation.yield()
                doneContinuation.finish()
            }
            throw error
        }

        // If close() was called while dial was in-flight, the connection
        // succeeded but the client is already torn down. Clean up and throw.
        guard !closed else {
            await connection.close()
            throw WspulseError.connectionClosed
        }

        connected = true
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

    // MARK: - URL Scheme Normalization

    /// Convert `http://` to `ws://` and `https://` to `wss://`.
    ///
    /// Unsupported or missing schemes trigger `preconditionFailure`
    /// because `URLSessionWebSocketTask` raises an uncatchable
    /// `NSException` for non-ws/wss schemes.
    private static func normalizeScheme(_ url: URL) -> URL {
        guard
            var components = URLComponents(
                url: url, resolvingAgainstBaseURL: false
            )
        else {
            preconditionFailure("wspulse: failed to parse URL")
        }

        switch components.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        case "ws", "wss":
            return url
        default:
            preconditionFailure(
                "wspulse: unsupported url scheme "
                    + "\"\(components.scheme ?? "(missing)")\", "
                    + "use ws://, wss://, http://, or https://"
            )
        }

        guard let result = components.url else {
            preconditionFailure(
                "wspulse: failed to rebuild URL after scheme conversion"
            )
        }
        return result
    }

    /// Permanently terminate the connection and stop any reconnect loop.
    ///
    /// Idempotent: calling more than once is safe.
    public func close() async {
        guard !closed else { return }
        let wasReconnecting = reconnecting
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

        // Only fire callbacks if the client was previously connected.
        // Per the behaviour contract, no callbacks fire if connect() was
        // never called or if the initial dial failed.
        if connected {
            // On clean close while CONNECTED, fire onTransportDrop(nil)
            // before onDisconnect. When close() is called while reconnecting,
            // handleTransportDrop already fired — do not fire again.
            if !wasReconnecting {
                options.onTransportDrop?(nil)
            }
            options.onDisconnect?(nil)
        }
        doneContinuation.yield()
        doneContinuation.finish()
    }
}
