# wspulse/client-swift

[![CI](https://github.com/wspulse/client-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/wspulse/client-swift/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-5.10+-orange.svg?logo=swift)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2016+%20%7C%20macOS%2013+%20%7C%20watchOS%209+%20%7C%20tvOS%2016+-blue.svg)](https://developer.apple.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A Swift WebSocket client with optional automatic reconnection, designed for use with [wspulse/server](https://github.com/wspulse/server).

Works on **iOS 16+**, **macOS 13+**, **watchOS 9+**, and **tvOS 16+** via `URLSessionWebSocketTask`. Zero external dependencies.

**Status:** v0 — API is being stabilized. Package: `WspulseClient` ([Swift Package Manager](https://www.swift.org/documentation/package-manager/)).

---

## Design Goals

- Thin client: connect, send, receive, auto-reconnect
- Matches server-side `Frame` wire format via JSON text frames
- Exponential backoff with configurable retries (equal jitter)
- Transport drop vs. permanent disconnect callbacks
- Swift Structured Concurrency (`actor`, `async/await`) with `Sendable` safety
- Zero external dependencies

---

## Install

### Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/wspulse/client-swift.git", from: "0.1.0"),
]
```

Then add `WspulseClient` to your target's dependencies:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "WspulseClient", package: "client-swift"),
    ]
)
```

### Xcode

1. File → Add Package Dependencies...
2. Enter: `https://github.com/wspulse/client-swift`
3. Select version rule and add to your target.

---

## Quick Start

```swift
import WspulseClient

let client = WspulseClient(
    url: URL(string: "ws://localhost:8080/ws?room=r1&token=xyz")!,
    options: WspulseClientOptions(
        onMessage: { frame in
            print("[\(frame.event ?? "")] \(String(describing: frame.payload))")
        },
        autoReconnect: AutoReconnectOptions(
            maxRetries: 5,
            baseDelay: .seconds(1),
            maxDelay: .seconds(30)
        )
    )
)

try await client.connect()
try await client.send(Frame(event: "msg", payload: .object(["text": .string("hello")])))

// Wait until permanently disconnected
for await _ in client.done { }
```

### SwiftUI Example

```swift
import SwiftUI
import WspulseClient

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [String] = []
    private var client: WspulseClient?

    func connect() async throws {
        let client = WspulseClient(
            url: URL(string: "ws://localhost:8080/ws?room=chat")!,
            options: WspulseClientOptions(
                onMessage: { [weak self] frame in
                    Task { @MainActor in
                        if let text = frame.payload?.stringValue {
                            self?.messages.append(text)
                        }
                    }
                },
                autoReconnect: AutoReconnectOptions(
                    maxRetries: 10,
                    baseDelay: .seconds(1),
                    maxDelay: .seconds(30)
                )
            )
        )
        self.client = client
        try await client.connect()
    }

    func send(_ text: String) async throws {
        try await client?.send(Frame(
            event: "msg",
            payload: .object(["text": .string(text)])
        ))
    }

    func disconnect() async {
        await client?.close()
    }
}
```

---

## API Reference

### `WspulseClient` (actor)

| Method / Property | Signature                                   | Description                                       |
| ----------------- | ------------------------------------------- | ------------------------------------------------- |
| `init`            | `(url: URL, options: WspulseClientOptions)` | Create a client. Does not connect yet.            |
| `connect()`       | `async throws`                              | Establish the WebSocket connection.               |
| `send(_:)`        | `(Frame) async throws`                      | Enqueue a frame for delivery.                     |
| `close()`         | `async`                                     | Permanently close. Idempotent.                    |
| `done`            | `AsyncStream<Void>`                         | Yields once and finishes on permanent disconnect. |

### `Frame`

```swift
public struct Frame: Codable, Sendable {
    public var id: String?
    public var event: String?
    public var payload: AnyJSON?
}
```

### `WspulseError`

| Case               | When thrown / passed to `onDisconnect`                  |
| ------------------ | ------------------------------------------------------- |
| `connectionClosed` | `send()` called after `close()`                         |
| `sendBufferFull`   | Send buffer (256 frames) is full                        |
| `retriesExhausted` | Max reconnect retries exhausted → `onDisconnect`        |
| `connectionLost`   | Server drops and auto-reconnect is off → `onDisconnect` |

### `WspulseCodec` (protocol)

```swift
public protocol WspulseCodec: Sendable {
    var frameType: FrameType { get }
    func encode(_ frame: Frame) throws -> Data
    func decode(_ data: Data) throws -> Frame
}
```

Default: `JSONCodec` (JSON text frames).

---

## Configuration

### `WspulseClientOptions`

| Option            | Type                         | Default     | Description                                 |
| ----------------- | ---------------------------- | ----------- | ------------------------------------------- |
| `onMessage`       | `@Sendable (Frame) -> Void`  | no-op       | Called for every inbound frame.             |
| `onDisconnect`    | `@Sendable (Error?) -> Void` | no-op       | Called on permanent disconnect.             |
| `onReconnect`     | `@Sendable (Int) -> Void`    | no-op       | Called at each reconnect attempt (0-based). |
| `onTransportDrop` | `@Sendable (Error) -> Void`  | no-op       | Called when the transport drops.            |
| `autoReconnect`   | `AutoReconnectOptions?`      | `nil` (off) | Enable exponential backoff reconnect.       |
| `heartbeat`       | `HeartbeatOptions`           | 20s / 60s   | Client-side Ping/Pong interval.             |
| `writeWait`       | `Duration`                   | 10s         | Deadline for a single write operation.      |
| `maxMessageSize`  | `Int`                        | 1 MiB       | Max inbound message size.                   |
| `dialHeaders`     | `[String: String]`           | `[:]`       | Extra HTTP headers for WebSocket upgrade.   |
| `codec`           | `any WspulseCodec`           | `JSONCodec` | Wire-format codec.                          |

### `AutoReconnectOptions`

| Field        | Type       | Description                   |
| ------------ | ---------- | ----------------------------- |
| `maxRetries` | `Int`      | Max retries (≤ 0 = unlimited) |
| `baseDelay`  | `Duration` | Initial backoff delay         |
| `maxDelay`   | `Duration` | Maximum backoff delay         |

### `HeartbeatOptions`

| Field        | Type       | Default | Description           |
| ------------ | ---------- | ------- | --------------------- |
| `pingPeriod` | `Duration` | 20s     | Ping send interval    |
| `pongWait`   | `Duration` | 60s     | Pong receive deadline |

---

## Backoff Formula

```
delay  = min(baseDelay * 2^attempt, maxDelay)
jitter = uniform random in [0.5, 1.0]
result = delay * jitter
```

Matches `client-go` exactly. Any deviation is a bug.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
