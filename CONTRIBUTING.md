# Contributing to wspulse/client-swift

Thank you for your interest in contributing. This document describes the process and conventions expected for all contributions.

## Before You Start

- Open an issue to discuss significant changes before starting work.
- For bug fixes, write a failing test that reproduces the issue before modifying production code. The PR must include this test.
- For new features, confirm scope and API design in an issue first.

## Development Setup

```bash
git clone https://github.com/wspulse/client-swift
cd client-swift
swift build
```

Requires:
- **Swift 5.10+** via **Xcode 15.3+** (recommended) — provides both the compiler and `xcrun swift-format`.
- Alternatively, the swift.org open-source toolchain; note that `make fmt` requires `swift-format` to be available via `xcrun`, which comes bundled with Xcode but must be installed separately when using the open-source toolchain.
- **SwiftLint** (`brew install swiftlint`) for `make lint` and `make fmt`.

## Pre-Commit Checklist

Run `make check` before every commit. It runs in order:

1. `make lint` — runs SwiftLint in strict mode; must pass with zero warnings
2. `make test` — runs unit tests; must pass

To auto-fix formatting, run `make fmt` (requires `xcrun swift-format` + SwiftLint).

If any step fails, do not commit.

## Commit Messages

Follow the format in [`.github/instructions/commit-message-instructions.md`](.github/instructions/commit-message-instructions.md):

```
<type>: <subject>

1.<reason> → <change>
```

All commit messages must be in English.

## Naming Conventions

- **Type names** must use full words — no abbreviations. Write `Connection`, not `Conn`.
- **Variable and parameter names** follow standard Swift style: short names for local scope (`url`, `err`, `frame`), descriptive names for stored properties.

## Actor Safety

`send()` and `close()` are actor-isolated methods on `WspulseClient`. All shared state is protected by the actor boundary. Every spawned `Task` must have an explicit cancellation path. `close()` must cancel all internal Tasks and `await` their completion before returning.

## Sendable Conformance

All public types must conform to `Sendable`. Callbacks must be `@Sendable` closures. The project builds with Swift 6 strict concurrency checking enabled.

## API Compatibility

wspulse/client-swift follows semantic versioning. Any change that removes, renames, or alters the signature of a public symbol is a **breaking change** and requires a major version bump.

- Before removing a symbol, mark it with `@available(*, deprecated, message: "Use Xxx instead")` in a minor release.
- Adding a requirement to a public protocol is also a breaking change.
- When in doubt, add a new symbol alongside the old one.

## Pull Request Guidelines

- One PR per logical change.
- Do not reformat code unrelated to your change — it creates noise in the diff.
- All CI checks must pass before review.
- Describe what changed and why, not just what the diff shows.
