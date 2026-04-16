# ``WspulseClient``

A Swift WebSocket client with optional automatic reconnection, designed for use with wspulse/server.

## Overview

WspulseClient provides a thin, actor-isolated WebSocket client for Apple platforms
(iOS 16+, macOS 13+, watchOS 9+, tvOS 16+). It uses `URLSessionWebSocketTask`
for transport and has zero external dependencies.

Key features:

- **Auto-reconnect** with exponential backoff and equal jitter.
- **Transport drop vs. permanent disconnect** callbacks for fine-grained lifecycle control.
- **Bounded send buffer** with backpressure (256 frames).
- **Actor-isolated** `send()` and `close()` — safe to call from any `Task`.

## Topics

### Essentials

- ``WspulseClient/WspulseClient``
- ``Frame``
- ``WspulseClientOptions``

### Configuration

- ``AutoReconnectOptions``

### Codec

- ``WspulseCodec``
- ``JSONCodec``
- ``FrameType``

### Data

- ``AnyJSON``

### Errors

- ``WspulseError``
