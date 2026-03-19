import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Internal actor wrapping `URLSessionWebSocketTask` for connection management.
actor ConnectionActor {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private let maxMessageSize: Int

    init(maxMessageSize: Int) {
        self.maxMessageSize = maxMessageSize
    }

    /// Open a WebSocket connection to the given URL with optional headers.
    func dial(url: URL, headers: [String: String]) {
        let configuration = URLSessionConfiguration.default
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = maxMessageSize
        self.session = session
        self.task = task
        task.resume()
    }

    /// Send data over the WebSocket. Uses text or binary message based on frame type.
    func send(_ data: Data, frameType: FrameType) async throws {
        guard let task else {
            throw WspulseError.connectionClosed
        }
        let message: URLSessionWebSocketTask.Message
        switch frameType {
        case .text:
            guard let string = String(data: data, encoding: .utf8) else {
                throw WspulseError.connectionClosed
            }
            message = .string(string)
        case .binary:
            message = .data(data)
        }
        try await task.send(message)
    }

    /// Receive the next message from the WebSocket.
    func receive() async throws -> Data {
        guard let task else {
            throw WspulseError.connectionClosed
        }
        let message = try await task.receive()
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else {
                throw WspulseError.connectionClosed
            }
            return data
        case .data(let data):
            return data
        @unknown default:
            throw WspulseError.connectionClosed
        }
    }

    /// Send a WebSocket ping and wait for the pong.
    func sendPing() async throws {
        guard let task else {
            throw WspulseError.connectionClosed
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Close the WebSocket connection with a normal closure code.
    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    /// Close with a specific close code (e.g. for protocol errors).
    func close(code: URLSessionWebSocketTask.CloseCode) {
        task?.cancel(with: code, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }
}
