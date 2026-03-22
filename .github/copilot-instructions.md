# Copilot Instructions — wspulse/client-swift

## Project Overview

wspulse/client-swift is a **WebSocket client library for Apple platforms** (iOS 16+, macOS 13+, watchOS 9+, tvOS 16+) with automatic reconnection and exponential backoff. Package name: `WspulseClient` (Swift Package Manager). Uses `URLSessionWebSocketTask` for transport, **Swift Structured Concurrency** (`async/await`, `actor`) for lifecycle management, and has **zero external dependencies**.

## Architecture

- **`Sources/WspulseClient/WspulseClient.swift`** — `public actor WspulseClient`: entry point with `connect()`, `send()`, `close()`, `done`. Internal `Task`s: `readLoop`, `writeLoop`, `reconnectLoop`, `pingLoop`.
- **`Sources/WspulseClient/WspulseClientOptions.swift`** — `WspulseClientOptions` value type with all configuration (callbacks, reconnect, heartbeat, codec).
- **`Sources/WspulseClient/Codec.swift`** — `WspulseCodec` protocol, `FrameType` enum, `JSONCodec` default implementation.
- **`Sources/WspulseClient/Frame.swift`** — `struct Frame: Codable, Sendable` (`id`, `event`, `payload` — all optional).
- **`Sources/WspulseClient/AnyJSON.swift`** — `enum AnyJSON: Codable, Sendable, Equatable` for type-erased JSON values.
- **`Sources/WspulseClient/Errors.swift`** — `enum WspulseError: Error, Sendable` hierarchy.
- **`Sources/WspulseClient/Backoff.swift`** — `backoff(attempt:base:max:)` function for exponential delay with equal jitter (matches Go implementation).
- **`Sources/WspulseClient/ConnectionActor.swift`** — Internal `actor` wrapping `URLSessionWebSocketTask` (dial, send, close, receive).

## Development Workflow

```bash
make build      # swift build
make test       # unit tests (excludes integration)
make test-integration  # integration tests (requires Go testserver)
make lint       # SwiftLint --strict
make fmt        # SwiftLint --fix
make check      # lint + unit test (pre-commit gate)
make clean      # swift package clean
```

## Conventions

- **Swift style**: Swift 6 strict concurrency mode (`StrictConcurrency` enabled), `actor` for shared mutable state, `Sendable` conformance on all public types, `@Sendable` closures for callbacks.
- **Naming**:
  - **Type names** must use full words — no abbreviations. Write `Connection`, not `Conn`; `Configuration`, not `Cfg`.
  - **Variable and parameter names** follow standard Swift style: short names for local scope (`url`, `err`, `frame`), descriptive names for stored properties.
- **Markdown**: no emojis in documentation files.
- **Git**:
  - Follow the commit message rules in [commit-message-instructions.md](instructions/commit-message-instructions.md).
  - All commit messages in English.
  - Each commit must represent exactly one logical change.
  - Before every commit, run `make check`.
  - **Branch strategy**: never push directly to `develop` or `main`.
    - `feat/<name>` or `feature/<name>` — new feature
    - `refactor/<name>` — restructure without behaviour change
    - `bugfix/<name>` — bug fix
    - `fix/<name>` — quick fix (e.g. config, docs, CI)
    - `chore/<name>` — maintenance, CI/CD, dependencies, docs
    - CI triggers on all branch prefixes above and on PRs targeting `main`/`develop`. Tags do **not** trigger CI (the tag is created after CI already passed). Open a PR into `develop`; `develop` requires status checks to pass.
- **Tests**: in `Tests/WspulseClientTests/`. Cover happy path and at least one error path. Required for new public functions. Integration tests use a Go echo server from `testserver/`.
  - **Test-first for bug fixes**: **mandatory** — see Critical Rule 8 for the required step-by-step procedure. Do not touch production code without a prior failing test.
- **API compatibility**:
  - Public symbols are a contract. Changing or removing any public identifier is a breaking change requiring a major version bump.
  - Adding a requirement to a public protocol breaks all external implementations — treat it as a breaking change.
  - Mark deprecated symbols with `@available(*, deprecated, message: "Use Xxx instead")` before removal.
- **Error format**: error descriptions prefixed with `wspulse: <context>`.
- **Dependency policy**: zero external dependencies. `URLSessionWebSocketTask` from Foundation is the only transport. Justify any new external dependency explicitly in the PR description.

## Critical Rules

1. **Read before write** — always read the target file, the [interface contract][contract-if], and the [behaviour contract][contract-bh] fully before editing.
2. **Minimal changes** — one concern per edit; no drive-by refactors.
3. **No hardcoded secrets** — all configuration via environment variables.
4. **Contract compliance** — API surface and behaviour must match the [interface contract][contract-if] and [behaviour contract][contract-bh]. When in doubt, re-read both contracts.
5. **Backoff formula parity** — must produce the same distribution as all other `wspulse/client-*` libraries. Any deviation is a bug.
6. **Actor isolation** — `send()` and `close()` are actor-isolated methods on `WspulseClient`. All shared state is protected by the actor boundary. Do not use `nonisolated` to escape actor isolation without explicit justification.
7. **Task lifecycle** — every spawned `Task` must have an explicit cancellation path. `close()` must cancel all internal Tasks and `await` their completion before returning. Use `withTaskCancellationHandler` where appropriate.
8. **STOP — test first, fix second** — when a bug is discovered or reported, do NOT touch production code until a failing test exists. Follow this exact sequence without skipping or reordering:
   1. Write a failing test that reproduces the bug.
   2. Run the test and confirm it **fails** (proving the test actually catches the bug).
   3. Fix the production code.
   4. Run the test again and confirm it **passes**.
   5. Run `make check` to verify nothing else broke.
   6. If you are about to edit production code and no failing test exists yet — stop and go back to step 1.
9. **STOP — before every commit, verify this checklist:**
   1. Run `make check` (lint → test) and confirm it passes. Skip if the commit contains only non-code changes (e.g. documentation, comments, Markdown).
   2. Run GitHub Copilot code review (`github.copilot.chat.review.changes`) on the working-tree diff and resolve every comment before proceeding.
   3. Commit message follows [commit-message-instructions.md](instructions/commit-message-instructions.md): correct type, subject ≤ 50 chars, numbered body items stating reason → change.
   4. This commit contains exactly one logical change — no unrelated modifications.
   5. If any item fails — fix it before committing.
10. **Accuracy** — if you have questions or need clarification, ask the user. Do not make assumptions without confirming.
11. **Language consistency** — when the user writes in Traditional Chinese, respond in Traditional Chinese; otherwise respond in English.
12. **No breaking changes without version bump** — never rename, remove, or change the signature of a public symbol without bumping the major version. When unsure, add alongside the old symbol and deprecate.
13. **Error policy — fail early, never at steady-state runtime** — Enforce errors at the earliest possible phase:
    1. Prefer compile-time enforcement via the type system and `Sendable`.
    2. **Setup-time programmer errors** (invalid options, missing required config): `preconditionFailure` or `fatalError`. These indicate a caller logic bug; crashing at startup is correct.
    3. **Steady-state runtime** (`send`, `close`, reconnect loops): throw typed `WspulseError` cases, never `fatalError`.

## Session Protocol

> Files under `doc/local/` are git-ignored and must **never** be committed.
> This applies to both plan files and `doc/local/ai-learning.md`.

- **At the start of every session**: check whether `doc/local/plan/` contains
  an in-progress plan for the current task, and read `doc/local/ai-learning.md`
  (if it exists) to recall past mistakes and techniques before writing any code.
- **Plan mode**: when implementing a new feature or multi-file fix, save a plan
  to `doc/local/plan/<feature-name>.md` before starting. Keep it updated with
  completed steps and any plan changes throughout the session.
- **AI learning log**: at the end of a session where mistakes were made or
  reusable techniques were discovered, append a short entry to
  `doc/local/ai-learning.md`. Entry format:
  `Date` / `Issue or Learning` / `Root Cause` / `Prevention Rule`.
  Append only — never overwrite existing entries.

[contract-if]: https://github.com/wspulse/.github/blob/main/doc/contracts/client/interface.md
[contract-bh]: https://github.com/wspulse/.github/blob/main/doc/contracts/client/behaviour.md
