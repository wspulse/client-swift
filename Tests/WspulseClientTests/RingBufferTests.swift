@testable import WspulseClient
import XCTest

// MARK: - A: Construction

final class RingBufferConstructionTests: XCTestCase {
    func testStartsEmptyWithCorrectCapacity() {
        var buf = RingBuffer<Int>(capacity: 4)
        XCTAssertEqual(buf.count, 0)
        XCTAssertTrue(buf.isEmpty)
        // Verify capacity is honoured: push 4 succeeds, push 5 fails.
        XCTAssertTrue(buf.push(1))
        XCTAssertTrue(buf.push(2))
        XCTAssertTrue(buf.push(3))
        XCTAssertTrue(buf.push(4))
        XCTAssertFalse(buf.push(5))
        XCTAssertEqual(buf.count, 4)
    }
}

// MARK: - B: Push

final class RingBufferPushTests: XCTestCase {
    func testPushReturnsTrueWhenNotFull() {
        var buf = RingBuffer<String>(capacity: 3)
        XCTAssertTrue(buf.push("a"))
        XCTAssertTrue(buf.push("b"))
        XCTAssertTrue(buf.push("c"))
        XCTAssertEqual(buf.count, 3)
    }

    func testPushReturnsFalseWhenFull() {
        var buf = RingBuffer<String>(capacity: 2)
        XCTAssertTrue(buf.push("a"))
        XCTAssertTrue(buf.push("b"))
        XCTAssertFalse(buf.push("c"))
        XCTAssertEqual(buf.count, 2)
    }
}

// MARK: - C: Peek

final class RingBufferPeekTests: XCTestCase {
    func testPeekReturnsFrontWithoutRemoving() {
        var buf = RingBuffer<String>(capacity: 3)
        buf.push("a")
        buf.push("b")
        XCTAssertEqual(buf.peek(), "a")
        XCTAssertEqual(buf.count, 2)
        XCTAssertEqual(buf.peek(), "a") // idempotent
    }

    func testPeekReturnsNilWhenEmpty() {
        let buf = RingBuffer<Int>(capacity: 2)
        XCTAssertNil(buf.peek())
    }
}

// MARK: - D: Dequeue

final class RingBufferDequeueTests: XCTestCase {
    func testDequeueReturnsFIFOOrder() {
        var buf = RingBuffer<String>(capacity: 3)
        buf.push("a")
        buf.push("b")
        buf.push("c")
        XCTAssertEqual(buf.dequeue(), "a")
        XCTAssertEqual(buf.dequeue(), "b")
        XCTAssertEqual(buf.dequeue(), "c")
        XCTAssertEqual(buf.count, 0)
    }

    func testDequeueReturnsNilWhenEmpty() {
        var buf = RingBuffer<Int>(capacity: 2)
        XCTAssertNil(buf.dequeue())
    }
}

// MARK: - E: Wrap-around

final class RingBufferWrapAroundTests: XCTestCase {
    func testPushAndDequeueWrapAroundCorrectly() {
        var buf = RingBuffer<String>(capacity: 3)
        // Fill to capacity
        buf.push("a")
        buf.push("b")
        buf.push("c")
        // Dequeue two — head advances
        XCTAssertEqual(buf.dequeue(), "a")
        XCTAssertEqual(buf.dequeue(), "b")
        // Push two more — tail wraps around
        XCTAssertTrue(buf.push("d"))
        XCTAssertTrue(buf.push("e"))
        // Verify FIFO order after wrap
        XCTAssertEqual(buf.dequeue(), "c")
        XCTAssertEqual(buf.dequeue(), "d")
        XCTAssertEqual(buf.dequeue(), "e")
        XCTAssertEqual(buf.count, 0)
    }

    func testMultipleWrapAroundCycles() {
        var buf = RingBuffer<Int>(capacity: 2)
        for cycle in 0..<5 {
            XCTAssertTrue(buf.push(cycle * 2))
            XCTAssertTrue(buf.push(cycle * 2 + 1))
            XCTAssertEqual(buf.dequeue(), cycle * 2)
            XCTAssertEqual(buf.dequeue(), cycle * 2 + 1)
            XCTAssertEqual(buf.count, 0)
        }
    }

    func testPushRejectsWhenFullAfterPartialDrainAndRefill() {
        var buf = RingBuffer<String>(capacity: 3)
        // Fill
        buf.push("a")
        buf.push("b")
        buf.push("c")
        // Drain 2
        buf.dequeue()
        buf.dequeue()
        // Refill to capacity (wraps around)
        XCTAssertTrue(buf.push("d"))
        XCTAssertTrue(buf.push("e"))
        // Now full — must reject
        XCTAssertFalse(buf.push("f"))
        XCTAssertEqual(buf.count, 3)
        // Verify FIFO
        XCTAssertEqual(buf.dequeue(), "c")
        XCTAssertEqual(buf.dequeue(), "d")
        XCTAssertEqual(buf.dequeue(), "e")
    }
}

// MARK: - F: Clear

final class RingBufferClearTests: XCTestCase {
    func testClearOnEmptyBufferIsNoOp() {
        var buf = RingBuffer<String>(capacity: 3)
        buf.clear()
        XCTAssertEqual(buf.count, 0)
        XCTAssertTrue(buf.isEmpty)
        XCTAssertTrue(buf.push("a"))
        XCTAssertEqual(buf.dequeue(), "a")
    }

    func testClearResetsBufferToEmpty() {
        var buf = RingBuffer<String>(capacity: 3)
        buf.push("a")
        buf.push("b")
        buf.push("c")
        buf.clear()
        XCTAssertEqual(buf.count, 0)
        XCTAssertTrue(buf.isEmpty)
        XCTAssertNil(buf.dequeue())
    }

    func testBufferIsUsableAfterClear() {
        var buf = RingBuffer<String>(capacity: 2)
        buf.push("a")
        buf.push("b")
        buf.clear()
        XCTAssertTrue(buf.push("c"))
        XCTAssertTrue(buf.push("d"))
        XCTAssertEqual(buf.dequeue(), "c")
        XCTAssertEqual(buf.dequeue(), "d")
    }

    func testClearWithNonZeroHead() {
        var buf = RingBuffer<String>(capacity: 3)
        buf.push("a")
        buf.push("b")
        buf.push("c")
        // Advance head past index 0
        buf.dequeue() // head=1
        buf.dequeue() // head=2
        // Push more to wrap
        buf.push("d")
        buf.push("e")
        // Now head=2, size=3 — clear must handle wrapped state
        buf.clear()
        XCTAssertEqual(buf.count, 0)
        XCTAssertNil(buf.dequeue())
        // Buffer must be fully usable after clear
        XCTAssertTrue(buf.push("f"))
        XCTAssertTrue(buf.push("g"))
        XCTAssertTrue(buf.push("h"))
        XCTAssertEqual(buf.dequeue(), "f")
        XCTAssertEqual(buf.dequeue(), "g")
        XCTAssertEqual(buf.dequeue(), "h")
    }
}

// MARK: - G: Capacity 1

final class RingBufferCapacityOneTests: XCTestCase {
    func testWorksWithCapacityOne() {
        var buf = RingBuffer<String>(capacity: 1)
        XCTAssertTrue(buf.push("a"))
        XCTAssertFalse(buf.push("b"))
        XCTAssertEqual(buf.dequeue(), "a")
        XCTAssertTrue(buf.push("b"))
        XCTAssertEqual(buf.dequeue(), "b")
        XCTAssertEqual(buf.count, 0)
    }
}
