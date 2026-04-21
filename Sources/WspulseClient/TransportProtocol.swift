import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Transport protocol for WebSocket connections.
///
/// ``ConnectionActor`` conforms to this in production; tests inject a mock.
/// Internal — not part of the public API surface.
protocol TransportProtocol: Actor {
    /// Open a WebSocket connection to the given URL with optional headers.
    func dial(url: URL, headers: [String: String]) async throws

    /// Send data over the WebSocket.
    func send(_ data: Data, wireType: WireType) async throws

    /// Receive the next message from the WebSocket.
    func receive() async throws -> Data

    /// Close the WebSocket connection with a normal closure code.
    func close()

    /// Close with a specific close code.
    func close(code: URLSessionWebSocketTask.CloseCode)
}
