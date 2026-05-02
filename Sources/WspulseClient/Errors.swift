import Foundation

/// Errors thrown by ``WspulseClient`` at steady-state runtime.
public enum WspulseError: Error, Sendable, Equatable {
    /// `send()` called after the client is permanently closed.
    case connectionClosed

    /// Send buffer (256 frames) is full.
    case sendBufferFull

    /// Max reconnect retries exhausted. Passed to `onDisconnect`.
    case retriesExhausted

    /// Connection lost (server drop or write timeout) while auto-reconnect is off.
    /// Passed to `onDisconnect`.
    case connectionLost

    /// Codec produced non-UTF8 data for a text-mode WebSocket frame.
    case encodingFailed

    /// Server sent a WebSocket close frame. Carries the close code and reason
    /// as reported by Foundation. When the close frame has no status body,
    /// ``StatusCode/noStatusReceived`` (1005) is synthesized per RFC 6455 §7.1.5.
    ///
    /// Delivered to ``WspulseClientOptions/onTransportDrop`` when a close
    /// frame is received from the server.
    case serverClosed(code: StatusCode, reason: String)
}

extension WspulseError: LocalizedError {
    public var errorDescription: String? { description }
}

extension WspulseError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .connectionClosed:
            return "wspulse: connection closed"
        case .sendBufferFull:
            return "wspulse: send buffer full"
        case .retriesExhausted:
            return "wspulse: retries exhausted"
        case .connectionLost:
            return "wspulse: connection lost"
        case .encodingFailed:
            return "wspulse: codec produced non-UTF8 data for text frame"
        case .serverClosed(let code, let reason):
            if reason.isEmpty {
                return "wspulse: server closed connection: code=\(code.rawValue)"
            }
            // String(reflecting:) wraps the value in quotes and escapes
            // embedded quotes, newlines, and other control characters.
            return "wspulse: server closed connection: code=\(code.rawValue), reason=\(String(reflecting: reason))"
        }
    }
}
