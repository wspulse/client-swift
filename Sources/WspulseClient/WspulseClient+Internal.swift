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
        writeSignalContinuation.finish()

        var newCont: AsyncStream<Void>.Continuation!
        let newStream = AsyncStream<Void> { newCont = $0 }
        writeSignal = newStream
        writeSignalContinuation = newCont

        writeTask = Task { [weak self] in
            guard let self else { return }
            for await _ in newStream {
                if Task.isCancelled { return }
                await self.drainBuffer()
            }
        }

        if !sendBuffer.isEmpty {
            writeSignalContinuation.yield()
        }
    }

    func startPingLoop() {
        let pingInterval = options.pingInterval
        let writeTimeout = options.writeTimeout
        let conn = connection
        let slp = sleeper

        pingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await slp.sleep(for: pingInterval)
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
                            try await slp.sleep(for: writeTimeout)
                            throw WspulseError.connectionLost
                        }
                        if let result = try await group.next() {
                            _ = result
                        }
                        group.cancelAll()
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    if let wspError = error as? WspulseError, wspError == .connectionLost {
                        options.logger.warning("wspulse/client: pong timeout, closing connection")
                    } else {
                        options.logger.warning("wspulse/client: ping failed: \(error)")
                    }
                    await self.handleTransportDrop(error: error)
                    return
                }
            }
        }
    }

    // MARK: - Reconnect

    func handleTransportDrop(error: Error) async {
        guard !closed, !reconnecting else { return }

        readTask?.cancel()
        writeTask?.cancel()
        pingTask?.cancel()

        options.onTransportDrop?(error)

        guard options.autoReconnect != nil else {
            options.logger.info("wspulse/client: transport dropped, no auto-reconnect")
            closed = true
            writeSignalContinuation.finish()
            await connection.close()

            // Await non-calling tasks. We cannot await the task that called
            // handleTransportDrop (readTask or pingTask) without deadlocking,
            // but writeTask is safe to await since it was cancelled above and
            // the stream is finished.
            await writeTask?.value
            writeTask = nil

            options.onDisconnect?(WspulseError.connectionLost)
            doneContinuation.yield()
            doneContinuation.finish()
            return
        }

        options.logger.info("wspulse/client: transport dropped, starting reconnect")
        reconnecting = true
        await connection.close()
        startReconnectLoop()
    }

    private func startReconnectLoop() {
        guard let reconnectOptions = options.autoReconnect else { return }
        let slp = sleeper
        let jitter = randomJitter

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            var attempt = 0

            while !Task.isCancelled {
                let delay = backoff(
                    attempt: attempt,
                    base: reconnectOptions.baseDelay,
                    max: reconnectOptions.maxDelay,
                    randomJitter: jitter
                )

                options.logger.debug("wspulse/client: reconnect attempt=\(attempt) delay=\(delay)")

                do {
                    try await slp.sleep(for: delay)
                } catch {
                    return
                }

                if Task.isCancelled { return }

                let succeeded = await self.attemptReconnect()

                if Task.isCancelled { return }

                if succeeded {
                    options.logger.info("wspulse/client: reconnected")
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
            options.logger.debug("wspulse/client: reconnect dial failed: \(error)")
            return false
        }
    }

    private func reconnected() async {
        // Finish the old write stream so the old writeTask can exit its for-await loop,
        // then await all old cancelled tasks before creating replacements.
        // This guarantees close() only needs to track the current set of tasks.
        writeSignalContinuation.finish()
        await readTask?.value
        await writeTask?.value
        await pingTask?.value

        reconnecting = false
        startReadLoop()
        startWriteLoop()
        startPingLoop()
        writeSignalContinuation.yield()

        options.onTransportRestore?()
    }

    func reconnectExhausted() async {
        guard !closed else { return }
        options.logger.warning("wspulse/client: max retries exhausted")
        closed = true
        reconnecting = false
        writeSignalContinuation.finish()
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
            options.logger.warning("wspulse/client: decode failed, frame dropped: \(error)")
            return nil
        }
    }

    func handleMessage(_ frame: Frame) {
        options.onMessage?(frame)
    }

    func drainBuffer() async {
        let writeTimeout = options.writeTimeout
        let conn = connection
        let frameType = options.codec.frameType
        let slp = sleeper
        while !sendBuffer.isEmpty {
            guard let data = sendBuffer.peek() else { break }
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await conn.send(data, frameType: frameType)
                    }
                    group.addTask {
                        try await slp.sleep(for: writeTimeout)
                        throw WspulseError.connectionLost
                    }
                    if let result = try await group.next() {
                        _ = result
                    }
                    group.cancelAll()
                }
                sendBuffer.dequeue()
            } catch is CancellationError {
                return
            } catch let error as WspulseError where error == .encodingFailed {
                // Encoding error is not a transport issue — drop the frame
                // and continue draining. Reconnecting would fail identically.
                sendBuffer.dequeue()
                options.logger.warning("wspulse/client: frame dropped (encoding failed)")
            } catch {
                if closed { return }
                options.logger.warning("wspulse/client: write failed: \(error)")
                await handleTransportDrop(error: error)
                return
            }
        }
    }
}
