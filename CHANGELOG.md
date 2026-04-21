# Changelog

## [Unreleased]

## [0.6.0] - 2026-04-21

### Changed

- **BREAKING**: `Frame` renamed to `Message` — aligns with upstream `wspulse/core` rename. The application-layer type is now `Message`; "frame" is reserved for the WebSocket protocol layer (RFC 6455).
- **BREAKING**: `FrameType` enum renamed to `WireType`.
- **BREAKING**: `WspulseCodec.frameType` property renamed to `wireType`.
- **BREAKING**: `WspulseCodec.encode(_:)` and `decode(_:)` parameter/return type changed from `Frame` to `Message`.
- **BREAKING**: `WspulseClient.send(_:)` parameter type changed from `Frame` to `Message`.
- **BREAKING**: `WspulseClientOptions.onMessage` callback type changed from `(Frame) -> Void` to `(Message) -> Void`.
- File renamed: `Frame.swift` to `Message.swift`.

## [0.5.1] - 2026-04-18

### Fixed

- Deadlock when `writeTask` detects a transport drop with `autoReconnect` disabled — `handleTransportDrop` no longer self-awaits the calling task (#30)

## [0.5.0] - 2026-04-17

### Removed

- **BREAKING**: `HeartbeatOptions` and `heartbeat` option — client-side ping is removed;
  dead-connection detection is now handled exclusively by the Hub's server-side heartbeat.


## [0.4.1] - 2026-04-09

### Changed

- Internal send buffer replaced with `RingBuffer<Data>` — O(1) dequeue instead of O(n) `Array.removeFirst()`. No API or behaviour changes.


## [0.4.0] - 2026-04-06

### Added

- `connect()` auto-converts `http://` to `ws://` and `https://` to `wss://` (case-insensitive per RFC 3986). Unsupported or missing schemes trigger precondition failure.
- `sendBufferSize` option — configurable outbound buffer capacity [1, 4096], default 256
- Internal `TransportProtocol` for WebSocket transport abstraction (enables mock-based testing)
- 17 deterministic component tests using `MockTransport` — zero network I/O, no testserver dependency
- `Sleeper` protocol (`sleep(for:) async throws`) with `RealSleeper` production wrapper
- `sleeper:` and `randomJitter:` parameters on the internal `WspulseClient` initializer for test injection
- `backoff()` receives an injectable `randomJitter:` closure for deterministic jitter in tests
- `FakeSleeper` actor in the test target: credit-based, handles `advance()` called before or after `sleep(for:)`, supports cooperative task cancellation so cancelled tasks exit cleanly
- Pong-timeout and reconnect component tests now use virtual sleeps instead of real-time waits

### Changed

- **BREAKING**: `onTransportDrop` callback signature changed from `(@Sendable (Error) -> Void)?` to `(@Sendable (Error?) -> Void)?`. The callback now fires on user-initiated close with `nil`, guaranteeing exactly one invocation per transport lifecycle. In reconnect scenarios each transport drop produces one invocation; a subsequent clean `close()` produces one more.
- CI no longer runs integration tests (`test-integration` job removed); component tests cover all scenarios

### Removed

- **BREAKING**: `Frame.id` field removed — transport layer does not use it. Applications needing message IDs should use payload.


## [0.3.0] - 2026-03-24

### Added

- `onTransportRestore` callback option, fired after a successful reconnect

### Removed

- `onReconnect` callback option (replaced by `onTransportRestore`) (**breaking**)


## [0.2.0] - 2026-03-22

### Fixed

- `reconnected()` orphaned old read/write/ping tasks by overwriting references
  without awaiting them. Now awaits old tasks before creating replacements.

### Changed

- **BREAKING**: negative `maxRetries` now triggers precondition failure instead
  of being treated as unlimited. Use `0` for unlimited retries.
- Validation error messages use fully-qualified field names (`heartbeat.pongWait`,
  `autoReconnect.baseDelay`) to match the config validation contract.
- Added upper-bound validation for all configurable options.
- Doc comments on option properties now include allowed ranges.

### Added

- Unit tests: codec failure decoding, ConnectionActor multiple close,
  send-after-close-with-code, send buffer initial state.
- DocC catalog and SPI configuration.


## [0.1.0] - 2026-03-22

### Added

- Project scaffold: SPM package, Makefile, CI/CD workflows, SwiftLint
- `Frame` struct (now `Message`) (`id`, `event`, `payload` — all optional, `Codable`, `Sendable`)
- `AnyJSON` type-erased Codable JSON value
- `WspulseCodec` protocol with `JSONCodec` default
- `WspulseClientOptions` value type with all configuration
- `backoff()` function with equal jitter (matches `client-go` formula)
- Error types: `WspulseError.connectionClosed`, `.sendBufferFull`, `.retriesExhausted`, `.connectionLost`, `.encodingFailed`
- `WspulseClient` actor: `connect()`, `send()`, `close()`, `done`
- Auto-reconnect with exponential backoff, configurable `maxRetries`, `baseDelay`, `maxDelay`
- Heartbeat: client-side Ping/Pong with `pingPeriod` and `pongWait`
- `writeWait`: write deadline per WebSocket send
- `maxMessageSize`: inbound message size enforcement
- `dialHeaders`: custom HTTP headers for WebSocket upgrade
- Bounded 256-frame send buffer with non-blocking `send()`
- Logging via `os.Logger` (enabled by default)
- 99 unit tests + 16 integration tests (9 scenarios + 7 additional)
- README with quick-start, SwiftUI example, API reference

[Unreleased]: https://github.com/wspulse/client-swift/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/wspulse/client-swift/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/wspulse/client-swift/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/wspulse/client-swift/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/wspulse/client-swift/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/wspulse/client-swift/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/wspulse/client-swift/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/wspulse/client-swift/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/wspulse/client-swift/releases/tag/v0.1.0
