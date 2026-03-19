@testable import WspulseClient
import XCTest

final class BackoffTests: XCTestCase {
    func testAttemptZeroReturnsWithinRange() {
        let base = Duration.seconds(1)
        let max = Duration.seconds(30)
        for _ in 0..<100 {
            let delay = backoff(attempt: 0, base: base, max: max)
            let seconds = durationToSeconds(delay)
            // attempt=0 → delay = min(1 * 2^0, 30) = 1
            // jitter ∈ [0.5, 1.0] → result ∈ [0.5, 1.0]
            XCTAssertGreaterThanOrEqual(seconds, 0.5)
            XCTAssertLessThanOrEqual(seconds, 1.0)
        }
    }

    func testExponentialGrowth() {
        let base = Duration.seconds(1)
        let max = Duration.seconds(120)
        // attempt=3 → delay = min(1 * 2^3, 120) = 8
        // jitter ∈ [0.5, 1.0] → result ∈ [4.0, 8.0]
        for _ in 0..<100 {
            let delay = backoff(attempt: 3, base: base, max: max)
            let seconds = durationToSeconds(delay)
            XCTAssertGreaterThanOrEqual(seconds, 4.0, "delay must be >= 4.0 for attempt 3")
            XCTAssertLessThanOrEqual(seconds, 8.0, "delay must be <= 8.0 for attempt 3")
        }
    }

    func testCapsAtMaxDelay() {
        let base = Duration.seconds(1)
        let max = Duration.seconds(10)
        // attempt=20 → delay = min(1 * 2^20, 10) = 10
        // jitter ∈ [0.5, 1.0] → result ∈ [5.0, 10.0]
        for _ in 0..<100 {
            let delay = backoff(attempt: 20, base: base, max: max)
            let seconds = durationToSeconds(delay)
            XCTAssertGreaterThanOrEqual(seconds, 5.0)
            XCTAssertLessThanOrEqual(seconds, 10.0)
        }
    }

    func testLargeAttemptDoesNotOverflow() {
        let base = Duration.seconds(1)
        let max = Duration.seconds(60)
        // attempt=100 → clamped to shift=62; raw capped at max=60
        let delay = backoff(attempt: 100, base: base, max: max)
        let seconds = durationToSeconds(delay)
        XCTAssertGreaterThanOrEqual(seconds, 30.0)
        XCTAssertLessThanOrEqual(seconds, 60.0)
    }

    func testJitterDistribution() {
        // Run many iterations and check that we see values both above and below the midpoint
        let base = Duration.seconds(2)
        let max = Duration.seconds(100)
        // attempt=0 → delay=2, jitter range [1.0, 2.0], midpoint=1.5
        var belowMid = 0
        var aboveMid = 0
        let iterations = 1000
        for _ in 0..<iterations {
            let delay = backoff(attempt: 0, base: base, max: max)
            let seconds = durationToSeconds(delay)
            if seconds < 1.5 {
                belowMid += 1
            } else {
                aboveMid += 1
            }
        }
        // Both should be well represented (at least 20% each)
        XCTAssertGreaterThan(belowMid, iterations / 5, "Expected some values below midpoint")
        XCTAssertGreaterThan(aboveMid, iterations / 5, "Expected some values above midpoint")
    }

    // MARK: - Helpers

    private func durationToSeconds(_ dur: Duration) -> Double {
        Double(dur.components.seconds) + Double(dur.components.attoseconds) * 1e-18
    }
}
