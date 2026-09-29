import Testing
@testable import FanCurveCore

@Suite struct WatchdogPolicyTests {
    @Test func aFreshHeartbeatKeepsTheDaemonInCharge() {
        #expect(!WatchdogPolicy.shouldRelease(heartbeatAge: 0.4, secondsSinceWake: nil))
        #expect(!WatchdogPolicy.shouldRelease(heartbeatAge: 5.0, secondsSinceWake: nil))
    }

    @Test func aStaleHeartbeatHandsTheFansBack() {
        #expect(WatchdogPolicy.shouldRelease(heartbeatAge: 5.1, secondsSinceWake: nil))
        #expect(WatchdogPolicy.shouldRelease(heartbeatAge: 600, secondsSinceWake: 3600))
    }

    @Test func noHeartbeatFileHandsTheFansBack() {
        #expect(WatchdogPolicy.shouldRelease(heartbeatAge: nil, secondsSinceWake: nil))
    }

    @Test func theFirstFifteenSecondsAfterWakeAreExempt() {
        #expect(!WatchdogPolicy.shouldRelease(heartbeatAge: 40, secondsSinceWake: 14.9))
        #expect(!WatchdogPolicy.shouldRelease(heartbeatAge: nil, secondsSinceWake: 0))
        #expect(WatchdogPolicy.shouldRelease(heartbeatAge: 40, secondsSinceWake: 15))
    }

    @Test func sleptBetweenNeedsTheWallClockToOutrunUptimeByMoreThanTheThreshold() {
        #expect(!WatchdogPolicy.sleptBetween(wallSeconds: 1.0, uptimeSeconds: 1.0))
        #expect(WatchdogPolicy.sleptBetween(wallSeconds: 3.1, uptimeSeconds: 1.0))
        #expect(!WatchdogPolicy.sleptBetween(wallSeconds: 2.9, uptimeSeconds: 1.0))
        #expect(!WatchdogPolicy.sleptBetween(wallSeconds: 0.5, uptimeSeconds: 1.0))
    }
}
