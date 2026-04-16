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
        }
    }
}
