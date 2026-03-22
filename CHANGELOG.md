# Changelog

## [Unreleased]

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

[Unreleased]: https://github.com/wspulse/client-swift/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/wspulse/client-swift/releases/tag/v0.1.0
