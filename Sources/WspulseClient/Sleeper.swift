/// Protocol for sleeping to allow injection in tests.
///
/// Conforming types must be `Sendable` so they can be captured across
/// actor boundaries inside Task closures.
protocol Sleeper: Sendable {
	/// Suspend the current task for the given duration.
	/// Throws `CancellationError` when the calling task is cancelled.
	func sleep(for duration: Duration) async throws
}

/// Production implementation that delegates to `Task.sleep`.
struct RealSleeper: Sleeper {
	func sleep(for duration: Duration) async throws {
		try await Task.sleep(for: duration)
	}
}
