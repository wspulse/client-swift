import Foundation

/// Declares whether a codec produces text frames or binary frames.
public enum FrameType: Sendable {
    case text
    case binary
}

/// Encodes and decodes ``Frame`` values for WebSocket transmission.
public protocol WspulseCodec: Sendable {
    /// Whether this codec produces text frames (opcode 1) or binary frames (opcode 2).
    var frameType: FrameType { get }

    /// Serialize a Frame into wire data.
    func encode(_ frame: Frame) throws -> Data

    /// Deserialize received wire data into a Frame.
    func decode(_ data: Data) throws -> Frame
}

/// Default JSON codec. Serializes Frames as JSON text frames.
public struct JSONCodec: WspulseCodec, Sendable {
    public let frameType: FrameType = .text

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func encode(_ frame: Frame) throws -> Data {
        try encoder.encode(frame)
    }

    public func decode(_ data: Data) throws -> Frame {
        try decoder.decode(Frame.self, from: data)
    }
}
