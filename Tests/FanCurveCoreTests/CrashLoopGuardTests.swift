import Testing
@testable import FanCurveCore

@Suite struct CrashLoopGuardTests {
    @Test func fifthStartWithinAMinuteTrips() {
        var starts: [Double] = []
        for time in [0.0, 10, 20, 30] {
            let result = CrashLoopGuard.recordStart(at: time, previous: starts)
            #expect(!result.tripped)
            starts = result.starts
        }
        #expect(CrashLoopGuard.recordStart(at: 40, previous: starts).tripped)
    }

    @Test func startsOlderThanTheWindowExpire() {
        let result = CrashLoopGuard.recordStart(at: 100, previous: [0, 10, 20, 30, 40])
        #expect(result.starts == [100])
        #expect(!result.tripped)
    }

    @Test func futureTimestampsAreDropped() {
        #expect(CrashLoopGuard.recordStart(at: 50, previous: [60, 70]).starts == [50])
    }
}
