# TODOS

Items deferred from PR review. Each entry links to the originating comment.

---

## close() during in-flight connect fires unexpected callbacks

**Issue**: wspulse/client-swift#15
**Source**: PR #13 review comment on `WspulseClient.swift:225`

`started` is set to `true` before `connection.dial()` returns. Because `connect()` suspends at the dial await point, a concurrent `close()` call sees `started == true` and fires `onTransportDrop(nil)` + `onDisconnect(nil)` even though no connection was established. Additionally, after the interleaved `close()`, `connect()` may resume from a successful dial and call `startReadLoop()` / `startWriteLoop()` / `startPingLoop()` without checking `closed`, potentially spawning tasks that are never cancelled.

**Fix direction**: Introduce a separate `connected: Bool` flag set only after `connection.dial()` returns successfully. Gate callbacks in `close()` on `connected` instead of `started`. After dial, check `closed` before starting loops.

**Note**: client-go, client-ts, and client-kt use a factory pattern where the client handle is returned only after dial succeeds, so this race cannot occur in those SDKs.
