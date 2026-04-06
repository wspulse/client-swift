import Foundation

/// Compute the backoff delay for a reconnect attempt using exponential backoff with equal jitter.
///
/// Formula (matches `client-go` exactly):
/// ```
/// delay  = min(baseDelay * 2^attempt, maxDelay)
/// jitter = uniform random in [0.5, 1.0]
/// result = delay * jitter
/// ```
///
/// - Parameters:
///   - attempt: The 0-based reconnect attempt number.
///   - base: The initial backoff delay.
///   - max: The maximum backoff delay cap.
/// - Returns: The jittered backoff duration.
func backoff(
    attempt: Int,
    base: Duration,
    max: Duration,
    randomJitter: @Sendable () -> Double = { Double.random(in: 0.5...1.0) }
) -> Duration {
    let clamped = attempt < 0 ? 0 : attempt
    let shift = min(clamped, 62)
    let multiplier = Double(1 << shift)
    let baseSeconds = Double(base.components.seconds) + Double(base.components.attoseconds) * 1e-18
    let maxSeconds = Double(max.components.seconds) + Double(max.components.attoseconds) * 1e-18
    let raw = Swift.min(baseSeconds * multiplier, maxSeconds)
    let jitter = randomJitter()
    let result = raw * jitter
    let nanos = result * 1_000_000_000
    let clampedNanos = Swift.min(Swift.max(nanos, Double(Int64.min)), Double(Int64.max))
    return .nanoseconds(Int64(clampedNanos))
}
