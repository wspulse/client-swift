# Changelog

## [Unreleased]

### Added

- `sendBufferSize` option — configurable outbound buffer capacity [1, 4096], default 256

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

[Unreleased]: https://github.com/wspulse/client-swift/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/wspulse/client-swift/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/wspulse/client-swift/releases/tag/v0.1.0
