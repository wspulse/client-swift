# TODOS

Items deferred from PR review. Each entry links to the originating comment.

---

## Integration tests: ConnectionActor.receive() serverClosed translation path

**Origin**: [PR #36](https://github.com/wspulse/client-swift/pull/36) —
comments [#3123994911](https://github.com/wspulse/client-swift/pull/36#discussion_r3123994911)
and [#3123994976](https://github.com/wspulse/client-swift/pull/36#discussion_r3123994976)

**What**: `ConnectionActor.receive()` contains two logic branches that are not exercised by
unit tests because they depend on `URLSessionWebSocketDelegate.didCloseWith:`, a Foundation
callback that can only fire from a real `URLSessionWebSocketTask`:

1. Real server close frame (non-pseudo code) → `throw WspulseError.serverClosed(...)`
2. Pseudo-code (1005, 1006, 1015) → `pseudoCloseCodes.contains()` guard → rethrow original error

**Why deferred**: Mocking `URLSession` at the delegate level requires `URLProtocol` interception
or a third-party HTTP stubbing library — cost disproportionate to coverage value for a
Foundation abstraction boundary.

**Resolution**: Cover both paths in the integration test suite using a real `testserver`:
- Test A: server sends close frame with code 1001 → assert `onTransportDrop` receives `.serverClosed(code: .goingAway, ...)`
- Test B: server drops TCP without close handshake → assert `onTransportDrop` receives a
  non-`WspulseError` error (URLError, etc.), confirming pseudo-code filtering passes through correctly
