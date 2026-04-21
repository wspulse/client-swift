import Foundation
import os

// Configuration upper bounds.
private let maxWriteWait: Duration = .seconds(30)
private let maxMsgSizeBytes = 64 * 1_048_576
private let maxBaseDelay: Duration = .seconds(60)
private let maxDelayLimit: Duration = .seconds(300)
private let maxRetriesLimit = 32
private let maxSendBufferSize = 4096

/// Configuration for automatic reconnection with exponential backoff.
public struct AutoReconnectOptions: Sendable {
    /// Maximum number of retries. `0` means unlimited. Range: 0...32.
    public var maxRetries: Int

    /// Initial backoff delay before the first retry. Range: (0s, 60s].
    public var baseDelay: Duration

    /// Maximum backoff delay cap. Must be >= `baseDelay`. Range: [baseDelay, 5m].
    public var maxDelay: Duration

    public init(
        maxRetries: Int = 0, baseDelay: Duration = .seconds(1), maxDelay: Duration = .seconds(30)
    ) {
        precondition(maxRetries >= 0, "wspulse: autoReconnect.maxRetries must be non-negative")
        precondition(baseDelay > .zero, "wspulse: autoReconnect.baseDelay must be positive")
        precondition(
            baseDelay <= maxBaseDelay, "wspulse: autoReconnect.baseDelay exceeds maximum (1m)")
        precondition(
            maxDelay >= baseDelay,
            "wspulse: autoReconnect.maxDelay must be >= autoReconnect.baseDelay")
        precondition(
            maxDelay <= maxDelayLimit, "wspulse: autoReconnect.maxDelay exceeds maximum (5m)")
        if maxRetries > 0 {
            precondition(
                maxRetries <= maxRetriesLimit,
                "wspulse: autoReconnect.maxRetries exceeds maximum (32)")
        }
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }
}

/// All configuration options for ``WspulseClient``.
public struct WspulseClientOptions: Sendable {
    /// Called for every inbound message decoded by the codec.
    public var onMessage: (@Sendable (Message) -> Void)?

    /// Called on permanent disconnect. `nil` error = clean close.
    public var onDisconnect: (@Sendable (Error?) -> Void)?

    /// Called after a successful reconnect when the new transport is ready.
    /// Does not fire on the initial connection.
    public var onTransportRestore: (@Sendable () -> Void)?

    /// Called each time the underlying transport drops (before any reconnect).
    /// Also fires with `nil` on user-initiated ``WspulseClient/close()`` when
    /// closing an active transport. If the transport already dropped and the
    /// reconnect loop is active, a subsequent ``WspulseClient/close()`` does
    /// not emit another `nil` — exactly one invocation per transport lifecycle.
    public var onTransportDrop: (@Sendable (Error?) -> Void)?

    /// Enable exponential backoff reconnect. `nil` = disabled.
    public var autoReconnect: AutoReconnectOptions?

    /// Deadline for a single write operation.
    public var writeWait: Duration

    /// Max inbound message size in bytes. `0` disables the limit. Connection closed if exceeded.
    public var maxMessageSize: Int

    /// Extra HTTP headers sent during WebSocket upgrade.
    public var dialHeaders: [String: String]

    /// Capacity of the outbound message buffer. Range: [1, 4096]. Default: 256.
    public var sendBufferSize: Int

    /// Wire-format codec for encoding/decoding Messages.
    public var codec: any WspulseCodec

    /// Logger for internal diagnostics. Enabled by default.
    public var logger: os.Logger

    public init(
        onMessage: (@Sendable (Message) -> Void)? = nil,
        onDisconnect: (@Sendable (Error?) -> Void)? = nil,
        onTransportRestore: (@Sendable () -> Void)? = nil,
        onTransportDrop: (@Sendable (Error?) -> Void)? = nil,
        autoReconnect: AutoReconnectOptions? = nil,
        writeWait: Duration = .seconds(10),
        maxMessageSize: Int = 1_048_576,
        sendBufferSize: Int = 256,
        dialHeaders: [String: String] = [:],
        codec: any WspulseCodec = JSONCodec(),
        logger: os.Logger = Logger(subsystem: "com.wspulse", category: "WspulseClient")
    ) {
        precondition(maxMessageSize >= 0, "wspulse: maxMessageSize must be non-negative")
        precondition(
            maxMessageSize <= maxMsgSizeBytes, "wspulse: maxMessageSize exceeds maximum (64 MiB)")
        precondition(writeWait > .zero, "wspulse: writeWait must be positive")
        precondition(writeWait <= maxWriteWait, "wspulse: writeWait exceeds maximum (30s)")
        precondition(sendBufferSize >= 1, "wspulse: sendBufferSize must be at least 1")
        precondition(
            sendBufferSize <= maxSendBufferSize,
            "wspulse: sendBufferSize exceeds maximum (\(maxSendBufferSize))"
        )
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
        self.onTransportRestore = onTransportRestore
        self.onTransportDrop = onTransportDrop
        self.autoReconnect = autoReconnect
        self.writeWait = writeWait
        self.maxMessageSize = maxMessageSize
        self.sendBufferSize = sendBufferSize
        self.dialHeaders = dialHeaders
        self.codec = codec
        self.logger = logger
    }
}
