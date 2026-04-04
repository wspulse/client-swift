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

## Frame Format

The default `JSONCodec` encodes frames as JSON text frames:

```json
{
  "event": "chat.message",
  "payload": { "text": "hello" }
}
```

The `event` field is the routing key on the server side. Set `frame.event` to match the handler registered with `r.On("chat.message", ...)` on the server. The `payload` field carries arbitrary data expressed as `AnyJSON`.

```swift
// Send a typed frame — server routes by "event"
try await client.send(Frame(
    event: "chat.message",
    payload: .object(["text": .string("hello world")])
))

// Receive typed frames in onMessage
WspulseClientOptions(
    onMessage: { frame in
        switch frame.event {
        case "chat.message": handleMessage(frame)
        case "chat.ack":     handleAck(frame)
        default: break
        }
    }
)
```

To use a custom wire format, implement `WspulseCodec`:

```swift
struct ProtobufCodec: WspulseCodec {
    var frameType: FrameType { .binary }
    func encode(_ frame: Frame) throws -> Data { /* serialize */ }
    func decode(_ data: Data) throws -> Frame  { /* deserialize */ }
}

let client = WspulseClient(
    url: url,
    options: WspulseClientOptions(codec: ProtobufCodec())
)
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
| `logger`          | `os.Logger`                  | enabled     | Logger for internal diagnostics.            |

### Logging

The client logs internal diagnostics via Apple's [unified logging system](https://developer.apple.com/documentation/os/logging) (`os.Logger`). Enabled by default with subsystem `com.wspulse`.

**Replace the logger** with your own:

```swift
let options = WspulseClientOptions(
    logger: Logger(subsystem: "com.myapp", category: "network")
)
```

**Disable logging:**

```swift
let options = WspulseClientOptions(
    logger: Logger(.disabled)
)
```

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

## Features

- **Auto-reconnect** — exponential backoff with configurable max retries, base delay, and max delay. Equal jitter formula: delay ∈ `[half, full]` where full = min(base × 2^attempt, max).
- **Transport drop callback** — `onTransportDrop` fires on every transport death, even when auto-reconnect follows. Useful for metrics and logging.
- **Permanent disconnect callback** — `onDisconnect` fires exactly once when the client is truly done (`close()` called, retries exhausted, or connection lost without auto-reconnect).
- **Heartbeat** — Client-side Ping/Pong keeps the connection alive and detects silently-dead servers.
- **Max message size** — Inbound messages exceeding `maxMessageSize` bytes drop the connection.
- **Backpressure** — bounded 256-frame send buffer; throws `WspulseError.sendBufferFull` when full.
- **Actor-isolated send** — `send()` enqueues only and returns immediately, safe to call from any `Task` without holding locks.
- **`done` AsyncStream** — yields once then finishes on permanent disconnect. `for await _ in client.done {}` suspends until the client is truly closed.
- **Idempotent close** — `close()` is safe to call multiple times concurrently.
- **Zero dependencies** — built on `URLSessionWebSocketTask`; no third-party libraries.

---

## Backoff Formula

```
delay  = min(baseDelay * 2^attempt, maxDelay)
jitter = uniform random in [0.5, 1.0]
result = delay * jitter
```

Matches `client-go` exactly. Any deviation is a bug.

---

## Development

```bash
make fmt              # auto-format with SwiftLint --fix
make check            # lint + unit tests (pre-commit gate)
make test             # unit + component tests
make clean            # remove build artifacts
```

---

## Related Modules

| Module                                                    | Description                          |
| --------------------------------------------------------- | ------------------------------------ |
| [wspulse/server](https://github.com/wspulse/server)       | WebSocket server                     |
| [wspulse/client-go](https://github.com/wspulse/client-go) | Go client (reference implementation) |
| [wspulse/client-ts](https://github.com/wspulse/client-ts) | TypeScript client                    |
| [wspulse/client-kt](https://github.com/wspulse/client-kt) | Kotlin client                        |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
