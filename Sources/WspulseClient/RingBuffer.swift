/// Fixed-capacity circular buffer with O(1) push and O(1) dequeue.
///
/// Used internally as the outbound send buffer. Not part of the
/// public API — consumers configure capacity via `sendBufferSize`
/// in ``WspulseClientOptions``.
struct RingBuffer<Element: Sendable>: Sendable {
    private var data: [Element?]
    private var head = 0
    private var size = 0
    private let capacity: Int

    /// Create a ring buffer with the given fixed capacity.
    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer: capacity must be at least 1")
        self.capacity = capacity
        self.data = [Element?](repeating: nil, count: capacity)
    }

    /// Number of elements currently in the buffer.
    var count: Int { size }

    /// Whether the buffer contains no elements.
    var isEmpty: Bool { size == 0 }

    /// Append an element to the back of the buffer.
    ///
    /// - Returns: `true` if the element was added, `false` if the
    ///   buffer is full.
    @discardableResult
    mutating func push(_ element: Element) -> Bool {
        if size >= capacity { return false }
        let index = (head + size) % capacity
        data[index] = element
        size += 1
        return true
    }

    /// Return the front element without removing it.
    ///
    /// - Returns: The oldest element, or `nil` if the buffer is empty.
    func peek() -> Element? {
        if size == 0 { return nil }
        return data[head]
    }

    /// Remove and return the front element.
    ///
    /// - Returns: The oldest element, or `nil` if the buffer is empty.
    @discardableResult
    mutating func dequeue() -> Element? {
        if size == 0 { return nil }
        let element = data[head]
        data[head] = nil
        head = (head + 1) % capacity
        size -= 1
        return element
    }

    /// Reset the buffer to empty without reallocating.
    mutating func clear() {
        for idx in 0..<size {
            data[(head + idx) % capacity] = nil
        }
        head = 0
        size = 0
    }
}
