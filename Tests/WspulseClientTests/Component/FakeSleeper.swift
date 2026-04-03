import Foundation

@testable import WspulseClient

/// A fake sleeper for deterministic component tests.
///
/// Uses a credit-based system so that `advance()` can be called before
/// or after the corresponding `sleep(for:)`. Each call to `advance()`
/// either wakes an already-suspended `sleep()` or banks a credit that
/// the next `sleep()` call will consume immediately.
///
/// Supports cooperative task cancellation: when a calling task is cancelled
/// while suspended in `sleep(for:)`, the continuation is removed and resumed
/// with `CancellationError` so the task can exit promptly.
actor FakeSleeper: Sleeper {
	private struct Waiter {
		let id: UUID
		let cont: CheckedContinuation<Void, Error>
	}

	private var credits = 0
	private var pending: [Waiter] = []

	/// Number of `sleep()` calls currently waiting to be resumed.
	var pendingCount: Int { pending.count }

	// MARK: - Sleeper

	func sleep(for _: Duration) async throws {
		try Task.checkCancellation()
		if credits > 0 {
			credits -= 1
			return
		}
		let id = UUID()
		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { cont in
				pending.append(Waiter(id: id, cont: cont))
			}
		} onCancel: {
			// Schedule cancellation on the actor; the Task may run before or
			// after the continuation is appended — the id lookup is safe either way.
			Task { await self.cancel(id: id) }
		}
	}

	// MARK: - Test helpers

	/// Resume `count` pending sleeps (or bank credits for future sleeps).
	func advance(count: Int = 1) {
		for _ in 0..<count {
			if !pending.isEmpty {
				pending.removeFirst().cont.resume()
			} else {
				credits += 1
			}
		}
	}

	/// Cancel all pending sleeps with `CancellationError`.
	func cancelAll() {
		credits = 0
		let waiters = pending
		pending.removeAll()
		for waiter in waiters { waiter.cont.resume(throwing: CancellationError()) }
	}

	// MARK: - Private

	private func cancel(id: UUID) {
		guard let idx = pending.firstIndex(where: { $0.id == id }) else { return }
		let cont = pending.remove(at: idx).cont
		cont.resume(throwing: CancellationError())
	}
}
