# AGENTS.md — wspulse/client-swift

This file is the entry point for all AI coding agents (GitHub Copilot, Codex,
Cursor, Claude, etc.). Full working rules are in
`.github/copilot-instructions.md` — read it completely before
making any changes.

---

## Quick Reference

**Package**: `WspulseClient` (SPM) | **Module**: `WspulseClient`

**Key files**:

- `Sources/WspulseClient/WspulseClient.swift` — `public actor WspulseClient`:
  `connect()`, `send()`, `close()`, `done`; internal read/write/reconnect/ping
  loop Tasks
- `Sources/WspulseClient/WspulseClientOptions.swift` — `WspulseClientOptions`
  value type with all configuration
- `Sources/WspulseClient/Codec.swift` — `WspulseCodec` protocol, `FrameType`
  enum, `JSONCodec` default
- `Sources/WspulseClient/Frame.swift` — `struct Frame: Codable, Sendable`
- `Sources/WspulseClient/AnyJSON.swift` — type-erased `Codable` JSON value
- `Sources/WspulseClient/Errors.swift` — `WspulseError` enum
- `Sources/WspulseClient/Backoff.swift` — `backoff(attempt:base:max:)` with
  equal jitter
- `Sources/WspulseClient/ConnectionActor.swift` — internal `actor` wrapping
  `URLSessionWebSocketTask`

**Pre-commit gate**: `make check` (lint → test)

---

## Non-negotiable Rules

1. **Read before write** — read the target file before any edit.
2. **Actor isolation** — `send()` and `close()` are actor-isolated methods.
   All shared state is protected by the actor. No `nonisolated` escape hatches
   without explicit justification.
3. **Task lifecycle** — every spawned `Task` must have an explicit cancellation
   path. `close()` must cancel all internal Tasks and `await` their completion.
4. **Sendable conformance** — all public types must conform to `Sendable`.
   Callbacks must be `@Sendable`.
5. **No breaking changes without version bump.**
6. **No hardcoded secrets.**
7. **Minimal changes** — one concern per edit; no drive-by refactors.

---

## Session Protocol

> `doc/local/` is git-ignored. Never commit files under it.

- **Start of session**: read `doc/local/ai-learning.md` (if present) and check
  `doc/local/plan/` for any in-progress plan.
- **Feature work**: save plan to `doc/local/plan/<feature-name>.md` first.
- **End of session**: append mistakes/learnings to `doc/local/ai-learning.md`.
  Format: `Date` / `Issue or Learning` / `Root Cause` / `Prevention Rule`.
