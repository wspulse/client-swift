# Changelog

## [Unreleased]

### Added

- Project scaffold: SPM package, Makefile, CI/CD workflows, SwiftLint
- `Frame` struct (`id`, `event`, `payload` — all optional, `Codable`, `Sendable`)
- `AnyJSON` type-erased Codable JSON value
- `WspulseCodec` protocol with `JSONCodec` default
- `WspulseClientOptions` value type with all configuration
- `backoff()` function with equal jitter (matches `client-go` formula)
- Error types: `WspulseError.connectionClosed`, `.sendBufferFull`, `.retriesExhausted`, `.connectionLost`
- `WspulseClient` actor: `connect()`, `send()`, `close()`, `done`
- Auto-reconnect with exponential backoff, configurable `maxRetries`, `baseDelay`, `maxDelay`
- Heartbeat: client-side Ping/Pong with `pingPeriod` and `pongWait`
- `writeWait`: write deadline per WebSocket send
- `maxMessageSize`: inbound message size enforcement
- `dialHeaders`: custom HTTP headers for WebSocket upgrade
- Bounded 256-frame send buffer with non-blocking `send()`
- Unit tests: backoff, Frame Codable, JSONCodec
- README with quick-start, SwiftUI example, API reference

[Unreleased]: https://github.com/wspulse/client-swift/commits/HEAD
