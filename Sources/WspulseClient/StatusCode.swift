import Foundation

/// WebSocket close status code (RFC 6455 §7.4).
///
/// Wraps the raw 16-bit integer close code. Callers use the static constants
/// for standard codes or construct directly for application-specific codes in
/// the private-use range `4000`–`4999`.
public struct StatusCode: RawRepresentable, Sendable, Hashable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// 1000 — Normal closure; the connection completed its purpose.
    public static let normalClosure = StatusCode(rawValue: 1000)

    /// 1001 — Endpoint is going away (server shutdown, browser navigation).
    public static let goingAway = StatusCode(rawValue: 1001)

    /// 1002 — Protocol error.
    public static let protocolError = StatusCode(rawValue: 1002)

    /// 1003 — Received data type the endpoint cannot accept.
    public static let unsupportedData = StatusCode(rawValue: 1003)

    /// 1005 — No status code was present in the close frame.
    ///
    /// RFC 6455 §7.4.1: MUST NOT be sent on the wire; synthesized by the
    /// client library when a received close frame has no status body.
    public static let noStatusReceived = StatusCode(rawValue: 1005)

    /// 1006 — Connection closed abnormally without a close frame.
    ///
    /// RFC 6455 §7.4.1: MUST NOT be sent on the wire; synthesized by the
    /// implementation when the TCP connection drops without a close handshake.
    public static let abnormalClosure = StatusCode(rawValue: 1006)

    /// 1007 — Received payload not consistent with message type (e.g. invalid UTF-8).
    public static let invalidFramePayloadData = StatusCode(rawValue: 1007)

    /// 1008 — Message violates endpoint policy.
    public static let policyViolation = StatusCode(rawValue: 1008)

    /// 1009 — Message too large for the endpoint to process.
    public static let messageTooBig = StatusCode(rawValue: 1009)

    /// 1010 — Client expected the server to negotiate required extensions.
    public static let mandatoryExtension = StatusCode(rawValue: 1010)

    /// 1011 — Server encountered an unexpected condition.
    public static let internalError = StatusCode(rawValue: 1011)

    /// 1015 — TLS handshake failed. Synthesized by the implementation; never on the wire.
    public static let tlsHandshake = StatusCode(rawValue: 1015)
}
