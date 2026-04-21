# Component Test Coverage -- client-swift

> **Contract:** all scenarios defined in the
> [test-scenarios contract](https://github.com/wspulse/.github/blob/main/doc/contracts/client/test-scenarios.md)

Component tests use a `MockTransport` actor (zero network I/O) injected via
`TransportProtocol`. No live testserver is required.

**Test classes:**
- `BasicTests` (connect, send, receive, close)
- `CallbackTests` (transport drop, disconnect, restore callbacks)
- `LifecycleTests` (close during reconnect, idempotent close, dial rejection)
- `MiscTests` (message fidelity, ordering, query params, concurrent sends)
- `ReconnectTests` (auto-reconnect, retries exhausted, pong timeout)

**Run:** `swift test --filter WspulseClientTests` (or `make test`)

## Scenario Matrix

| #   | Scenario                                                     | Test Name                                              |
| --- | ------------------------------------------------------------ | ------------------------------------------------------ |
| 1   | Connect -> send -> echo -> close clean                       | `testConnectSendReceiveCloseClean`                     |
| 2   | Transport error -> onTransportDrop + onDisconnect            | `testTransportErrorFiresTransportDropAndDisconnect`    |
| 3   | Auto-reconnect via MockDialerTransport                       | `testReconnectsAfterTransportDrop`                     |
| 4   | Max retries exhausted -> `onDisconnect(.retriesExhausted)`   | `testFiresRetriesExhaustedAfterMaxRetries`             |
| 5   | `close()` during reconnect -> `onDisconnect(nil)`            | `testCloseDuringReconnectFiresDisconnectNil`           |
| 6   | `send()` on closed client -> `.connectionClosed`             | `testSendAfterCloseThrowsConnectionClosed`             |
| 7   | Heartbeat pong timeout -> `.connectionLost`                  | `testPongTimeoutTriggersConnectionLost`                |
| 8   | Concurrent sends: no data race or interleaving               | `testConcurrentSendsDoNotRace`                         |
| 9   | Concurrent `close()` + transport drop -> onDisconnect once   | `testCloseRacingWithTransportDropFiresDisconnectOnce`  |

## Additional Tests

| Test Name                                         | What It Covers                                   |
| ------------------------------------------------- | ------------------------------------------------ |
| `testRoundTripsAllMessageFields`                  | Full Message field fidelity through codec        |
| `testHandlesDialRejectionGracefully`              | `connect()` throws when dial fails               |
| `testReceivesMessagesInOrder`                     | Message ordering preservation                    |
| `testConnectsWithQueryParams`                     | URL query parameters are passed through          |
| `testOnDisconnectFiresExactlyOnceOnClose`         | User-initiated close fires exactly one callback  |
| `testCloseIsIdempotent`                           | Multiple `close()` calls fire one callback       |
| `testTransportDropFiresOnDisconnect`              | Transport drop -> `onDisconnect(non-nil)`        |
| `testTransportRestoreNotOnInitialConnect`         | `onTransportRestore` only fires after reconnect  |

**Total: 17 component tests** (9 scenarios + 8 additional).

## Mock Transport Architecture

- **`MockTransport`** -- single-connection mock with `injectMessage()`, `injectError()`,
  `suppressPongs()`, and `setDialError()` for deterministic test control.
- **`MockDialerTransport`** -- sequences multiple `MockTransport` instances for reconnect
  tests. Each `dial()` advances to the next transport in the sequence.
