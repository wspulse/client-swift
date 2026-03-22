import Foundation

/// The minimal transport unit. All fields are optional at the wire layer.
public struct Frame: Codable, Sendable, Equatable {
    /// Opaque correlation ID. Omit if not needed.
    public var id: String?

    /// Application-defined event name.
    public var event: String?

    /// Opaque body. The client does not interpret this field.
    public var payload: AnyJSON?

    public init(id: String? = nil, event: String? = nil, payload: AnyJSON? = nil) {
        self.id = id
        self.event = event
        self.payload = payload
    }
}
