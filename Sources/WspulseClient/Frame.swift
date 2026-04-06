import Foundation

/// The minimal transport unit. All fields are optional at the wire layer.
public struct Frame: Codable, Sendable, Equatable {
    /// Application-defined event name.
    public var event: String?

    /// Opaque body. The client does not interpret this field.
    public var payload: AnyJSON?

    public init(event: String? = nil, payload: AnyJSON? = nil) {
        self.event = event
        self.payload = payload
    }
}
