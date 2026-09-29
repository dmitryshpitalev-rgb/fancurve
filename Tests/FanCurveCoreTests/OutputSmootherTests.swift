import Testing
@testable import FanCurveCore

@Suite struct OutputSmootherTests {
    let smoothing = Smoothing()  // up 25 %/s, hold 20 s, down 2 %/s, deadband 3 %

    @Test func risesAtMostAtUpRate() {
        var smoother = OutputSmoother()
        smoother.step(demand: 100, at: 0, smoothing: smoothing)
        #expect(smoother.step(demand: 100, at: 0.5, smoothing: smoothing) == 12.5)
        #expect(smoother.step(demand: 100, at: 1.0, smoothing: smoothing) == 25)
    }

    @Test func doesNotOvershootDemand() {
        var smoother = OutputSmoother()
        smoother.step(demand: 10, at: 0, smoothing: smoothing)
        #expect(smoother.step(demand: 10, at: 1, smoothing: smoothing) == 10)
    }

    @Test func holdsAfterLastRiseThenFallsAtDownRate() {
        var smoother = OutputSmoother(output: 50)
        smoother.step(demand: 50, at: 0, smoothing: smoothing)
        #expect(smoother.step(demand: 0, at: 10, smoothing: smoothing) == 50)
        #expect(smoother.step(demand: 0, at: 19.5, smoothing: smoothing) == 50)
        #expect(smoother.step(demand: 0, at: 20, smoothing: smoothing) == 49)
        #expect(smoother.step(demand: 0, at: 21, smoothing: smoothing) == 47)
    }

    @Test func demandReturningToOutputRestartsHold() {
        var smoother = OutputSmoother(output: 40)
        smoother.step(demand: 40, at: 0, smoothing: smoothing)
        smoother.step(demand: 0, at: 15, smoothing: smoothing)
        smoother.step(demand: 40, at: 16, smoothing: smoothing)
        #expect(smoother.step(demand: 0, at: 30, smoothing: smoothing) == 40)
    }

    @Test func neverFallsBelowDemand() {
        var smoother = OutputSmoother(output: 50)
        smoother.step(demand: 50, at: 0, smoothing: smoothing)
        smoother.step(demand: 45, at: 20, smoothing: smoothing)
        #expect(smoother.step(demand: 45, at: 30, smoothing: smoothing) == 45)
    }

    @Test func bypassJumpsImmediately() {
        var smoother = OutputSmoother()
        smoother.step(demand: 0, at: 0, smoothing: smoothing)
        #expect(smoother.step(demand: 100, at: 0.5, smoothing: smoothing, bypass: true) == 100)
    }

    @Test func clampsDemandToPercentRange() {
        var smoother = OutputSmoother()
        #expect(smoother.step(demand: 150, at: 0, smoothing: smoothing, bypass: true) == 100)
    }

    @Test func resetStartsFromGivenOutputAndHolds() {
        var smoother = OutputSmoother()
        smoother.reset(output: 35, at: 100)
        #expect(smoother.step(demand: 0, at: 110, smoothing: smoothing) == 35)
        #expect(smoother.step(demand: 60, at: 110.5, smoothing: smoothing) == 47.5)
    }

    /// As in ChannelFilter, time only moves forward: a step with an earlier timestamp is a no-op, or
    /// the next real tick computes an inflated dt from the rewound clock.
    @Test func staleTimestampLeavesOutputAndClockUnchanged() {
        let noHold = Smoothing(upPercentPerSecond: 25, holdSeconds: 0, downPercentPerSecond: 2, deadbandPercent: 3)
        var smoother = OutputSmoother(output: 50)
        smoother.step(demand: 50, at: 10, smoothing: noHold)
        // Stale/backward timestamp: output must not move.
        #expect(smoother.step(demand: 0, at: 5, smoothing: noHold) == 50)
        // A real tick shortly after the last accepted time (10, not the rejected 5): descent must be
        // rate * true elapsed (0.5 s), not rate * (10.5 - 5) as a rewound clock would compute.
        #expect(smoother.step(demand: 0, at: 10.5, smoothing: noHold) == 49)
    }

    /// A step at the last step's own time is a step of no time, not a stale one: a bypass there
    /// still restarts the hold.
    @Test func aBypassAtTheSameTimeRestartsTheHold() {
        var smoother = OutputSmoother(output: 90)
        smoother.step(demand: 90, at: 0, smoothing: smoothing)
        #expect(smoother.step(demand: 0, at: 20, smoothing: smoothing) == 50)  // the hold is over
        #expect(smoother.step(demand: 100, at: 20, smoothing: smoothing, bypass: true) == 100)
        #expect(smoother.step(demand: 0, at: 21, smoothing: smoothing) == 100)  // held again
    }
}

@Suite struct WriteGateTests {
    @Test func firstWriteAlwaysHappens() {
        #expect(WriteGate.shouldWrite(40, lastWritten: nil, deadband: 3))
    }

    @Test func changesInsideDeadbandAreSkipped() {
        #expect(!WriteGate.shouldWrite(42, lastWritten: 40, deadband: 3))
        #expect(WriteGate.shouldWrite(43, lastWritten: 40, deadband: 3))
        #expect(!WriteGate.shouldWrite(40, lastWritten: 40, deadband: 0))
    }

    @Test func extremesAreAlwaysWritten() {
        #expect(WriteGate.shouldWrite(0, lastWritten: 1, deadband: 3))
        #expect(WriteGate.shouldWrite(100, lastWritten: 98.5, deadband: 3))
    }
}
