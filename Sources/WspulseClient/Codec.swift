import Foundation

/// Declares whether a codec produces text frames or binary frames.
public enum WireType: Sendable {
    case text
    case binary
}

/// Encodes and decodes ``Message`` values for WebSocket transmission.
public protocol WspulseCodec: Sendable {
    /// Whether this codec produces text frames (opcode 1) or binary frames (opcode 2).
    var wireType: WireType { get }

    /// Serialize a Message into wire data.
    func encode(_ message: Message) throws -> Data

    /// Deserialize received wire data into a Message.
    func decode(_ data: Data) throws -> Message
}

/// Default JSON codec. Serializes Messages as JSON text frames.
public struct JSONCodec: WspulseCodec, Sendable {
    public let wireType: WireType = .text

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func encode(_ message: Message) throws -> Data {
        try encoder.encode(message)
    }

    public func decode(_ data: Data) throws -> Message {
        try decoder.decode(Message.self, from: data)
    }
}
