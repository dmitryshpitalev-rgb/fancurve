/// Fixed-capacity buffer that overwrites the oldest element when full.
public struct RingBuffer<Element> {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
    }

    public var count: Int { storage.count }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// The newest `n` elements (none for n <= 0), oldest first; copies only those.
    public func suffix(_ n: Int) -> [Element] {
        let count = storage.count
        let n = min(max(n, 0), count)
        return (count - n ..< count).map { storage[(head + $0) % count] }
    }
}

extension RingBuffer: Sendable where Element: Sendable {}
