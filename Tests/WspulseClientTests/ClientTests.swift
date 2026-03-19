import WspulseClient
import XCTest

// Integration tests against the Go testserver.
// These tests require the testserver binary to be available.
// Run with: swift test --filter ClientTests
// Or: make test-integration
final class ClientTests: XCTestCase {
    // TODO: Implement integration tests against Go testserver.
    //
    // Each test should:
    // 1. Build and start the testserver binary via Process
    // 2. Connect a WspulseClient to the testserver
    // 3. Verify the scenario behaviour
    // 4. Stop the testserver
    //
    // See doc/integration-tests.md for the full scenario matrix.

    func testPlaceholder() {
        // Placeholder — replaced by real integration tests in a future PR.
        XCTAssertTrue(true)
    }
}
