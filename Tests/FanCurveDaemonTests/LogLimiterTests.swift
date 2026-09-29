import Testing
@testable import FanCurveDaemon

@Suite struct LogLimiterTests {
    @Test func theSameMessageIsSuppressedForAMinute() {
        var limiter = LogLimiter()
        let first = limiter.shouldLog("hello", now: 0)
        let at59 = limiter.shouldLog("hello", now: 59)
        let at60 = limiter.shouldLog("hello", now: 60)
        #expect(first)
        #expect(!at59)
        #expect(at60)
    }

    @Test func differentMessagesEachGetTheirOwnMinute() {
        var limiter = LogLimiter()
        let a0 = limiter.shouldLog("a", now: 0)
        let b1 = limiter.shouldLog("b", now: 1)
        let a2 = limiter.shouldLog("a", now: 2)
        let b3 = limiter.shouldLog("b", now: 3)
        let a60 = limiter.shouldLog("a", now: 60)
        let b61 = limiter.shouldLog("b", now: 61)
        #expect(a0)
        #expect(b1)
        #expect(!a2)
        #expect(!b3)
        #expect(a60)
        #expect(b61)
    }
}
