import Foundation

// MARK: - Internal loops and reconnect logic

extension WspulseClient {
    // MARK: - Internal loops

    func startReadLoop() {
        let conn = connection
        readTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let data = try await conn.receive()
                    if let frame = await self.decodeFrame(data) {
                        await self.handleMessage(frame)
                    }
                } catch {
                    if Task.isCancelled { return }
                    await self.handleTransportDrop(error: error)
                    return
                }
            }
        }
    }

    func startWriteLoop() {
        // Create a fresh write-signal stream for this connection cycle so the new
        // write task gets its own iterator. AsyncStream supports only one active
        // iterator: if we reused the same stream, the old (cancelled) task's iterator
        // and the new task's iterator would compete and yields would be lost.
        //
        // Finish the old continuation first to prevent dangling references and
        // ensure yields to the old stream are not silently lost.
        writeSignalContinuation.finish()

        var newCont: AsyncStream<Void>.Continuation!
        let newStream = AsyncStream<Void> { newCont = $0 }
        writeSignal = newStream
        writeSignalContinuation = newCont

        writeTask = Task { [weak self] in
            guard let self else { return }
            // Iterate the captured stream directly to avoid an actor hop inside the
            // loop (var properties require await to access from outside the actor).
            for await _ in newStream {
                if Task.isCancelled { return }
                await self.drainBuffer()
            }
        }

        // If there are messages that were enqueued before this connection cycle
        // completed (e.g. while connect() was still dialing), make sure the new
        // write loop is kicked so it can begin draining the existing buffer.
        if !sendBuffer.isEmpty {
            writeSignalContinuation.yield()
        }
    }

    func startPingLoop() {
        let pingPeriod = options.heartbeat.pingPeriod
        let pongWait = options.heartbeat.pongWait
        let conn = connection

        pingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: pingPeriod)
                } catch {
                    return
                }
                if Task.isCancelled { return }

                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await conn.sendPing()
                        }
                        group.addTask {
                            try await Task.sleep(for: pongWait)
                            throw WspulseError.connectionLost
                        }
                        // First to complete wins; cancel the other.
                        if let result = try await group.next() {
                            _ = result
                        }
                        group.cancelAll()
                    }
                } catch {
                    if Task.isCancelled { return }
                    await self.handleTransportDrop(error: error)
                    return
                }
            }
        }
    }

    // MARK: - Reconnect

    func handleTransportDrop(error: Error) async {
        guard !closed, !reconnecting else { return }

        // Cancel current loops. We must NOT await them here because this
        // method is called from within readTask or pingTask — awaiting the
        // calling task would deadlock. Task cleanup is handled by close()
        // and reconnected() instead.
        readTask?.cancel()
        writeTask?.cancel()
        pingTask?.cancel()

        options.onTransportDrop?(error)

        guard options.autoReconnect != nil else {
            // No auto-reconnect: permanent disconnect.
            closed = true
            writeSignalContinuation.finish()
            await connection.close()
            options.onDisconnect?(error)
            doneContinuation.yield()
            doneContinuation.finish()
            return
        }

        reconnecting = true
        startReconnectLoop()
    }

    private func startReconnectLoop() {
        guard let reconnectOptions = options.autoReconnect else { return }

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            var attempt = 0

            while !Task.isCancelled {
                let delay = backoff(
                    attempt: attempt,
                    base: reconnectOptions.baseDelay,
                    max: reconnectOptions.maxDelay
                )

                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }

                if Task.isCancelled { return }

                await self.notifyReconnect(attempt: attempt)

                if Task.isCancelled { return }

                let succeeded = await self.attemptReconnect()

                if Task.isCancelled { return }

                if succeeded {
                    await self.reconnected()
                    return
                }

                attempt += 1
                if reconnectOptions.maxRetries > 0 && attempt >= reconnectOptions.maxRetries {
                    await self.reconnectExhausted()
                    return
                }
            }
        }
    }

    private func attemptReconnect() async -> Bool {
        await connection.close()
        do {
            try await connection.dial(url: url, headers: options.dialHeaders)
            try await connection.sendPing()
            return true
        } catch {
            return false
        }
    }

    private func reconnected() {
        reconnecting = false
        startReadLoop()
        startWriteLoop()
        startPingLoop()
        writeSignalContinuation.yield()
    }

    private func notifyReconnect(attempt: Int) {
        options.onReconnect?(attempt)
    }

    func reconnectExhausted() async {
        guard !closed else { return }
        closed = true
        reconnecting = false
        await connection.close()
        options.onDisconnect?(WspulseError.retriesExhausted)
        doneContinuation.yield()
        doneContinuation.finish()
    }

    // MARK: - Helpers

    func decodeFrame(_ data: Data) -> Frame? {
        do {
            return try options.codec.decode(data)
        } catch {
            // Skip malformed frames (matches client-kt behaviour).
            return nil
        }
    }

    func handleMessage(_ frame: Frame) {
        options.onMessage?(frame)
    }

    func drainBuffer() async {
        let writeWait = options.writeWait
        let conn = connection
        let frameType = options.codec.frameType
        while !sendBuffer.isEmpty {
            let data = sendBuffer[0]
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await conn.send(data, frameType: frameType)
                    }
                    group.addTask {
                        try await Task.sleep(for: writeWait)
                        throw WspulseError.connectionLost
                    }
                    if let result = try await group.next() {
                        _ = result
                    }
                    group.cancelAll()
                }
                sendBuffer.removeFirst()
            } catch {
                if closed { return }
                await handleTransportDrop(error: error)
                return
            }
        }
    }
}
