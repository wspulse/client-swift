import Foundation
import os

/// Configuration for automatic reconnection with exponential backoff.
public struct AutoReconnectOptions: Sendable {
    /// Maximum number of retries. Values ≤ 0 mean unlimited.
    public var maxRetries: Int

    /// Initial backoff delay before the first retry.
    public var baseDelay: Duration

    /// Maximum backoff delay cap.
    public var maxDelay: Duration

    public init(maxRetries: Int = 0, baseDelay: Duration = .seconds(1), maxDelay: Duration = .seconds(30)) {
        precondition(baseDelay > .zero, "wspulse: baseDelay must be positive")
        precondition(maxDelay >= baseDelay, "wspulse: maxDelay must be >= baseDelay")
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }
}

/// Configuration for client-side heartbeat (Ping/Pong).
public struct HeartbeatOptions: Sendable {
    /// Interval between Ping frames sent by the client.
    public var pingPeriod: Duration

    /// Maximum time to wait for a Pong reply before closing the connection.
    public var pongWait: Duration

    public init(pingPeriod: Duration = .seconds(20), pongWait: Duration = .seconds(60)) {
        precondition(pingPeriod > .zero, "wspulse: pingPeriod must be positive")
        precondition(pongWait > pingPeriod, "wspulse: pongWait must be greater than pingPeriod")
        self.pingPeriod = pingPeriod
        self.pongWait = pongWait
    }
}

/// All configuration options for ``WspulseClient``.
public struct WspulseClientOptions: Sendable {
    /// Called for every inbound frame decoded by the codec.
    public var onMessage: (@Sendable (Frame) -> Void)?

    /// Called on permanent disconnect. `nil` error = clean close.
    public var onDisconnect: (@Sendable (Error?) -> Void)?

    /// Called at each reconnect attempt. `attempt` is 0-based.
    public var onReconnect: (@Sendable (Int) -> Void)?

    /// Called each time the underlying transport drops (before any reconnect).
    public var onTransportDrop: (@Sendable (Error) -> Void)?

    /// Enable exponential backoff reconnect. `nil` = disabled.
    public var autoReconnect: AutoReconnectOptions?

    /// Client-side Ping/Pong interval.
    public var heartbeat: HeartbeatOptions

    /// Deadline for a single write operation.
    public var writeWait: Duration

    /// Max inbound message size in bytes. Connection closed if exceeded.
    public var maxMessageSize: Int

    /// Extra HTTP headers sent during WebSocket upgrade.
    public var dialHeaders: [String: String]

    /// Wire-format codec for encoding/decoding Frames.
    public var codec: any WspulseCodec

    /// Logger for internal diagnostics. Enabled by default.
    ///
    /// Pass `Logger(.disabled)` to suppress all log output.
    public var logger: os.Logger

    public init(
        onMessage: (@Sendable (Frame) -> Void)? = nil,
        onDisconnect: (@Sendable (Error?) -> Void)? = nil,
        onReconnect: (@Sendable (Int) -> Void)? = nil,
        onTransportDrop: (@Sendable (Error) -> Void)? = nil,
        autoReconnect: AutoReconnectOptions? = nil,
        heartbeat: HeartbeatOptions = HeartbeatOptions(),
        writeWait: Duration = .seconds(10),
        maxMessageSize: Int = 1_048_576,
        dialHeaders: [String: String] = [:],
        codec: any WspulseCodec = JSONCodec(),
        logger: os.Logger = Logger(subsystem: "com.wspulse", category: "WspulseClient")
    ) {
        precondition(maxMessageSize > 0, "wspulse: maxMessageSize must be positive")
        precondition(writeWait > .zero, "wspulse: writeWait must be positive")
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
        self.onReconnect = onReconnect
        self.onTransportDrop = onTransportDrop
        self.autoReconnect = autoReconnect
        self.heartbeat = heartbeat
        self.writeWait = writeWait
        self.maxMessageSize = maxMessageSize
        self.dialHeaders = dialHeaders
        self.codec = codec
        self.logger = logger
    }
}
