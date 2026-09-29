import Foundation
import Testing
@testable import FanCurveCore

@Suite struct ChannelFilterTests {
    @Test func firstSampleInitializesWithoutSmoothing() {
        var filter = ChannelFilter(tau: 2, lossTicks: 3)
        #expect(filter.update(50, at: 0) == 50)
    }

    @Test func stepResponseReaches63PercentAfterTau() {
        var filter = ChannelFilter(tau: 2, lossTicks: 3)
        filter.update(0, at: 0)
        for tick in 1...4 {
            filter.update(100, at: Double(tick) * 0.5)
        }
        #expect(abs((filter.value ?? -1) - 100 * (1 - exp(-1))) < 1e-9)
    }

    @Test func irregularIntervalsGiveTheSameResult() {
        var twoSteps = ChannelFilter(tau: 10, lossTicks: 3)
        var oneStep = ChannelFilter(tau: 10, lossTicks: 3)
        twoSteps.update(0, at: 0)
        oneStep.update(0, at: 0)
        twoSteps.update(60, at: 0.5)
        twoSteps.update(60, at: 2.0)
        oneStep.update(60, at: 2.0)
        #expect(abs((twoSteps.value ?? 0) - (oneStep.value ?? 0)) < 1e-9)
    }

    @Test func shortGapKeepsLastValue() {
        var filter = ChannelFilter(tau: 2, lossTicks: 3)
        filter.update(70, at: 0)
        #expect(filter.update(nil, at: 0.5) == 70)
        #expect(filter.update(nil, at: 1.0) == 70)
        #expect(filter.update(70, at: 1.5) == 70)
    }

    @Test func consecutiveMissesClearTheChannel() {
        var filter = ChannelFilter(tau: 2, lossTicks: 3)
        filter.update(70, at: 0)
        filter.update(nil, at: 0.5)
        filter.update(nil, at: 1.0)
        #expect(filter.update(nil, at: 1.5) == nil)
        #expect(filter.update(40, at: 2.0) == 40)
    }

    @Test func nonFiniteSamplesCountAsMissing() {
        var filter = ChannelFilter(tau: 2, lossTicks: 1)
        filter.update(70, at: 0)
        #expect(filter.update(.nan, at: 0.5) == nil)
    }

    @Test func resetClearsState() {
        var filter = ChannelFilter(tau: 2, lossTicks: 3)
        filter.update(70, at: 0)
        filter.reset()
        #expect(filter.value == nil)
        #expect(filter.update(30, at: 1) == 30)
    }

    @Test func staleTimestampDoesNotRewindTheClock() {
        var filter = ChannelFilter(tau: 2, lossTicks: 3)
        filter.update(0, at: 0)
        filter.update(0, at: 5)
        filter.update(100, at: 2)
        #expect(filter.value == 0)
        filter.update(100, at: 5.5)
        #expect(abs((filter.value ?? -1) - 100 * (1 - exp(-0.25))) < 1e-9)
    }

    @Test func reportsLossOnlyAfterTheLossThreshold() {
        var filter = ChannelFilter(tau: 2, lossTicks: 3)
        filter.update(70, at: 0)
        filter.update(nil, at: 0.5)
        filter.update(nil, at: 1.0)
        #expect(!filter.isLost)
        filter.update(nil, at: 1.5)
        #expect(filter.isLost)
        filter.update(50, at: 2.0)
        #expect(!filter.isLost)
    }
}
