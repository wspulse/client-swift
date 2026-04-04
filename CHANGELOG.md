# Changelog

## [Unreleased]

---

## [0.4.0] - 2026-04-04

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

- CI no longer runs integration tests (`test-integration` job removed); component tests cover all scenarios

### Removed

- **BREAKING**: `Frame.id` field removed — transport layer does not use it. Applications needing message IDs should use payload.

---

## [0.3.0] - 2026-03-24

### Added

- `onTransportRestore` callback option, fired after a successful reconnect

### Removed

- `onReconnect` callback option (replaced by `onTransportRestore`) (**breaking**)

---

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

---

## [0.1.0] - 2026-03-22

### Added

- Project scaffold: SPM package, Makefile, CI/CD workflows, SwiftLint
- `Frame` struct (`id`, `event`, `payload` — all optional, `Codable`, `Sendable`)
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

[Unreleased]: https://github.com/wspulse/client-swift/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/wspulse/client-swift/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/wspulse/client-swift/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/wspulse/client-swift/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/wspulse/client-swift/releases/tag/v0.1.0
