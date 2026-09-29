import Testing
@testable import FanCurveCore

@Suite struct RingBufferTests {
    @Test func keepsInsertionOrderBeforeFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        #expect(buffer.suffix(buffer.capacity) == [1, 2])
        #expect(buffer.count == 2)
    }

    @Test func overwritesOldestWhenFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for value in 1...5 {
            buffer.append(value)
        }
        #expect(buffer.suffix(buffer.capacity) == [3, 4, 5])
        #expect(buffer.count == 3)
    }

    @Test func suffixReturnsNewest() {
        var buffer = RingBuffer<Int>(capacity: 4)
        for value in 1...6 {
            buffer.append(value)
        }
        #expect(buffer.suffix(2) == [5, 6])
        #expect(buffer.suffix(10) == [3, 4, 5, 6])
    }

    @Test func suffixAsksForNothingOrMoreThanThereIs() {
        var buffer = RingBuffer<Int>(capacity: 4)
        #expect(buffer.suffix(3) == [])
        buffer.append(1)
        #expect(buffer.suffix(0) == [])
        #expect(buffer.suffix(-1) == [])
        #expect(buffer.suffix(3) == [1])
    }
}
