# Copilot Instructions — wspulse/client-swift

## Project Overview

wspulse/client-swift is a **WebSocket client library for Apple platforms** (iOS 16+, macOS 13+, watchOS 9+, tvOS 16+) with automatic reconnection and exponential backoff. Package name: `WspulseClient` (Swift Package Manager). Uses `URLSessionWebSocketTask` for transport, **Swift Structured Concurrency** (`async/await`, `actor`) for lifecycle management, and has **zero external dependencies**.

## Architecture

- **`Sources/WspulseClient/WspulseClient.swift`** — `public actor WspulseClient`: entry point with `connect()`, `send()`, `close()`, `done`. Internal `Task`s: `readLoop`, `writeLoop`, `reconnectLoop`, `pingLoop`.
- **`Sources/WspulseClient/WspulseClientOptions.swift`** — `WspulseClientOptions` value type with all configuration (callbacks, reconnect, heartbeat, codec).
- **`Sources/WspulseClient/Codec.swift`** — `WspulseCodec` protocol, `FrameType` enum, `JSONCodec` default implementation.
- **`Sources/WspulseClient/Frame.swift`** — `struct Frame: Codable, Sendable` (`event`, `payload` — all optional).
- **`Sources/WspulseClient/AnyJSON.swift`** — `enum AnyJSON: Codable, Sendable, Equatable` for type-erased JSON values.
- **`Sources/WspulseClient/Errors.swift`** — `enum WspulseError: Error, Sendable` hierarchy.
- **`Sources/WspulseClient/Backoff.swift`** — `backoff(attempt:base:max:)` function for exponential delay with equal jitter (matches Go implementation).
- **`Sources/WspulseClient/ConnectionActor.swift`** — Internal `actor` wrapping `URLSessionWebSocketTask` (dial, send, close, receive).

## Development Workflow

```bash
make build      # swift build
make test       # unit + component tests (excludes legacy integration)
make lint       # SwiftLint --strict
make fmt        # SwiftLint --fix
make check      # lint + test (pre-commit gate)
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
  - **Pull request description**: must follow the repo's `.github/PULL_REQUEST_TEMPLATE.md`. Fill in every section (Summary, Changes, Checklist). Do not invent custom formats.
- **Tests**: in `Tests/WspulseClientTests/`. Cover happy path and at least one error path. Required for new public functions. Component tests use `MockTransport` (via `TransportProtocol`) for deterministic testing without network I/O.
  - **Test-first for bug fixes**: **mandatory** — see Critical Rule 8 for the required step-by-step procedure. Do not touch production code without a prior failing test.
- **API compatibility**:
  - Public symbols are a contract. Changing or removing any public identifier is a breaking change requiring a major version bump.
  - Adding a requirement to a public protocol breaks all external implementations — treat it as a breaking change.
  - Mark deprecated symbols with `@available(*, deprecated, message: "Use Xxx instead")` before removal.
- **Error format**: error descriptions prefixed with `wspulse: <context>`.
- **Dependency policy**: zero external dependencies. `URLSessionWebSocketTask` from Foundation is the only transport. Justify any new external dependency explicitly in the PR description.
- **File encoding**: all files must be UTF-8 without BOM. Do not use any other encoding.

## Feature Workflow

All new features and design changes follow this process — do not skip steps:

1. **Plan** — write idea to `doc/local/plan/<name>.md` (local only, git-ignored)
2. **Quick discussion** — feasibility + value check
3. **Go / No-go** — kill or proceed
4. **Layer check** — transport layer (wspulse implements) or application layer (write docs recipe instead)
5. **Issue** — repo-scoped work: open issue on this repo. Cross-repo/global work: open issue on [`wspulse/.github`](https://github.com/wspulse/.github). Include summary, scope, impact assessment, priority label + milestone
6. **Design discussion** — API surface, cross-SDK parity, contract/protocol updates, edge cases
7. **Task** — feature branch from `develop`, implement with tests, CHANGELOG entry, PR following template. **Repo-scoped**: link PR to the issue. **Global**: each PR mentions the global issue (e.g., `wspulse/.github#N`); after opening a PR, comment on the global issue with the PR link

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
   2. Commit message follows [commit-message-instructions.md](instructions/commit-message-instructions.md): correct type, subject ≤ 50 chars, numbered body items stating reason → change.
   3. This commit contains exactly one logical change — no unrelated modifications.
   4. If any item fails — fix it before committing.
10. **Accuracy** — if you have questions or need clarification, ask the user. Do not make assumptions without confirming.
11. **Language consistency** — when the user writes in Traditional Chinese, respond in Traditional Chinese; otherwise respond in English.
12. **No breaking changes without version bump** — never rename, remove, or change the signature of a public symbol without bumping the major version. When unsure, add alongside the old symbol and deprecate.
13. **Error policy — fail early, never at steady-state runtime** — Enforce errors at the earliest possible phase:
    1. Prefer compile-time enforcement via the type system and `Sendable`.
    2. **Setup-time programmer errors** (invalid options, missing required config): `preconditionFailure` or `fatalError`. These indicate a caller logic bug; crashing at startup is correct.
    3. **Steady-state runtime** (`send`, `close`, reconnect loops): throw typed `WspulseError` cases, never `fatalError`.

## PR Comment Review — MANDATORY

When handling PR review comments, **every unresponded comment must be analyzed and responded to**. No comment may be silently ignored.

### 1. Fetch unresponded comments

Pull all comments that have not received a reply from the PR author. Bot-generated summaries (e.g. Copilot review overview) may be skipped; individual line comments from bots must still be evaluated.

### 2. Analyze each comment

Evaluate against:

| Criterion | Question |
|-----------|----------|
| **Validity** | Is the observation correct? Is the suggestion reasonable? |
| **Severity** | Is it a bug, a correctness issue, a design concern, or a style/preference nitpick? |
| **Cost** | What is the effort to address? Does the change introduce risk or scope creep? |

### 3. Present analysis for approval

Present all findings to the user before taking action. For each comment, show:
- The comment content and location
- Your assessment (validity, severity, cost)
- Your proposed decision (Fixed / Tracked / Won't fix / Not applicable) with reasoning

**Do not make any code changes or reply to comments until the user has reviewed and approved.** If there are disagreements, discuss until a consensus is reached.

### 4. Execute approved decisions

After approval, carry out each decision and respond on the PR:

- **`Fixed in {hash}. {what changed and why}`** — adopt and fix immediately. Bug and correctness issues must use this path unless the fix requires a separate PR due to scope.
- **`Tracked in TODOS.md — {reason for deferring}`** — adopt but defer. Add entry to repo root `TODOS.md` with context and PR comment link.
- **`Won't fix. {clear reasoning}`** — reject the suggestion with explanation.
- **`Not applicable — {explanation}`** — the comment does not apply (already handled, misunderstanding, duplicate, or already tracked in TODOS.md).

Duplicate or related comments may reference each other: `Same reasoning as {reference} above — {brief}`.

### 5. Zero unresponded comments before merge

The PR must have zero unaddressed comments before merge. This is a hard gate.

## Session Protocol

> Files under `doc/local/` are git-ignored and must **never** be committed.
> This includes plan files (`doc/local/plan/`), review records, and the AI learning log (`doc/local/ai-learning.md`).

### Start of every session — MANDATORY

**Do these steps before writing any code:**

1. Read `doc/local/ai-learning.md` **in full** to recall past mistakes. If the file is missing or empty, create it with the table header (see format below) before proceeding.
2. Check `doc/local/plan/` for any in-progress plan and read it fully.

### During feature work — doc before code

Before writing any production code, create or update `doc/local/plan/<feature-name>.md` with:

1. **What** — what are you changing or adding?
2. **Why** — what problem does it solve? What motivated this change?
3. **How** — what is the intended approach?

Keep it updated as the approach evolves. This is the primary cross-session context for understanding what was done and why.

For bug fixes, the failing test serves as the "what"; add a brief "why" and "how" to the plan file or `doc/local/ai-learning.md`.

### Review records

After conducting any review (code review, plan review, design review, PR review, etc.), record the findings for cross-session context:

- **Where to write**: this repo's `doc/local/`. If working in a multi-module workspace, also write to the workspace root's `doc/local/`.
- **Single truth**: write the full record in one location; the other location keeps a brief summary with a file path reference to the full record.
- **Acceptable formats**:
  1. Update the relevant plan file in `doc/local/plan/` with the review outcome.
  2. Dedicated review file in `doc/local/` if no relevant plan exists.
- **What to record**: review type, key findings, decisions made, action items, and resolution status.

### End of every session — MANDATORY

**Before closing the session, complete this checklist without exception:**

1. Append at least one entry to `doc/local/ai-learning.md` — **even if no mistakes were made**. Record what you confirmed, what technique worked, or what you observed. An empty file is a sign of non-compliance.
2. Update any in-progress plan in `doc/local/plan/` to reflect completed steps.
3. Verify `make check` passes in every module you edited.

**Entry format** for `doc/local/ai-learning.md`:

```
| Date       | Issue or Learning | Root Cause | Prevention Rule |
| ---------- | ----------------- | ---------- | --------------- |
| YYYY-MM-DD | <what happened or what you learned> | <why it happened> | <how to avoid it next time> |
```

**Writing to `ai-learning.md` is not optional. It is the primary cross-session improvement mechanism. An empty file proves the session protocol was ignored.**

[contract-if]: https://github.com/wspulse/.github/blob/main/doc/contracts/client/interface.md
[contract-bh]: https://github.com/wspulse/.github/blob/main/doc/contracts/client/behaviour.md
