# Integration Test Coverage — client-swift

> **Contract:** all scenarios defined in the
> [integration-test-scenarios contract](https://github.com/wspulse/.github/blob/main/doc/contracts/integration-test-scenarios.md)

Integration tests run against a live `wspulse/server` via the shared
[testserver](https://github.com/wspulse/testserver). The Go test server is spawned by
`Process` in `setUp` and killed in `tearDown`.

**Test class:** `ClientIntegrationTests` (in `Tests/WspulseClientTests/ClientIntegrationTests.swift`)
**Run:** `swift test --filter ClientIntegrationTests` (or `make test-integration`)

## Scenario Matrix

| #   | Scenario                                                     | Test Name                                             | Query Params      |
| --- | ------------------------------------------------------------ | ----------------------------------------------------- | ----------------- |
| 1   | Connect → send → echo → close clean                          | `testConnectSendEchoCloseClean`                       | —                 |
| 2   | Server drops → onTransportDrop + onDisconnect (no reconnect) | `testServerDropFiresTransportDropAndDisconnect`       | `?id=…`           |
| 3   | Auto-reconnect: server drops → reconnects within maxRetries  | `testReconnectsAfterKickAndResumesEcho`               | `?id=…`           |
| 4   | Max retries exhausted → `onDisconnect(.retriesExhausted)`    | `testFiresRetriesExhaustedAfterShutdown`              | `?id=…`           |
| 5   | `close()` during reconnect → loop stops, `onDisconnect(nil)` | `testCloseDuringReconnectFiresDisconnectNil`          | `?id=…`           |
| 6   | `send()` on closed client → `WspulseError.connectionClosed`  | `testSendAfterCloseThrowsConnectionClosed`            | —                 |
| 7   | Heartbeat pong timeout → `.connectionLost`                   | `testPongTimeoutTriggersConnectionLost`               | `?ignore_pings=1` |
| 8   | Concurrent sends: no data race or interleaving               | `testConcurrentSendsDoNotRace`                        | —                 |
| 9   | Concurrent `close()` + transport drop → onDisconnect once    | `testCloseRacingWithTransportDropFiresDisconnectOnce` | `?id=…`           |

## Additional Tests

| Test Name                                       | What It Covers                              |
| ----------------------------------------------- | ------------------------------------------- |
| `testRoundTripsAllFrameFields`                  | Full Frame field fidelity through the wire  |
| `testHandlesServerRejectionGracefully`          | Server returns HTTP 403 via `?reject=1`     |
| `testSendsMultipleFramesAndReceivesThemInOrder` | Message ordering preservation               |
| `testConnectsToSpecificRoomViaQueryParam`       | Room routing via `?room=…`                  |
| `testDetectsServerInitiatedKickViaControlAPI`   | `POST /kick?id=…` → `onDisconnect(non-nil)` |

**Total: 14 integration tests** (9 scenarios + 5 additional).
