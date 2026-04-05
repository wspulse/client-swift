import XCTest

@testable import WspulseClient

final class URLSchemeTests: XCTestCase {
    // MARK: - WebSocket schemes pass through unchanged

    func testWSPassthrough() async {
        let client = WspulseClient(
            url: URL(string: "ws://localhost:8080/path")!
        )
        let stored = await client.url
        XCTAssertEqual(stored.absoluteString, "ws://localhost:8080/path")
        await client.close()
    }

    func testWSSPassthrough() async {
        let client = WspulseClient(
            url: URL(string: "wss://example.com/ws")!
        )
        let stored = await client.url
        XCTAssertEqual(stored.absoluteString, "wss://example.com/ws")
        await client.close()
    }

    // MARK: - HTTP schemes are converted

    func testHTTPConvertedToWS() async {
        let client = WspulseClient(
            url: URL(string: "http://localhost:8080/path")!
        )
        let stored = await client.url
        XCTAssertEqual(stored.absoluteString, "ws://localhost:8080/path")
        await client.close()
    }

    func testHTTPSConvertedToWSS() async {
        let client = WspulseClient(
            url: URL(string: "https://example.com/ws")!
        )
        let stored = await client.url
        XCTAssertEqual(stored.absoluteString, "wss://example.com/ws")
        await client.close()
    }

    // MARK: - Conversion preserves port and query

    func testHTTPWithPortPreservesPort() async {
        let client = WspulseClient(
            url: URL(string: "http://localhost:9090/chat")!
        )
        let stored = await client.url
        XCTAssertEqual(stored.absoluteString, "ws://localhost:9090/chat")
        await client.close()
    }

    func testHTTPSWithPortAndQueryPreserved() async {
        let client = WspulseClient(
            url: URL(string: "https://example.com:443/ws?token=abc&room=1")!
        )
        let stored = await client.url
        XCTAssertEqual(
            stored.absoluteString,
            "wss://example.com:443/ws?token=abc&room=1"
        )
        await client.close()
    }

    // MARK: - Case-insensitive scheme handling

    func testUppercaseHTTPConverted() async {
        let client = WspulseClient(
            url: URL(string: "HTTP://localhost:8080/path")!
        )
        let stored = await client.url
        XCTAssertEqual(stored.scheme, "ws")
        await client.close()
    }

    func testMixedCaseHTTPSConverted() async {
        let client = WspulseClient(
            url: URL(string: "Https://example.com/ws")!
        )
        let stored = await client.url
        XCTAssertEqual(stored.scheme, "wss")
        await client.close()
    }
}
