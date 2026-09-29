import Testing
@testable import FanCurveCore

@Suite struct FanRangeTests {
    let fan = FanRange(minRPM: 2000, maxRPM: 5400)
    let ranges = [FanRange(minRPM: 1836, maxRPM: 5616), FanRange(minRPM: 1700, maxRPM: 5200)]

    @Test func mapsPercentToRPM() {
        #expect(fan.rpm(forPercent: 0) == 2000)
        #expect(fan.rpm(forPercent: 50) == 3700)
        #expect(fan.rpm(forPercent: 100) == 5400)
        #expect(fan.rpm(forPercent: 140) == 5400)
        #expect(fan.rpm(forPercent: -5) == 2000)
    }

    @Test func mapsRPMToPercent() {
        #expect(fan.percent(forRPM: 3700) == 50)
        #expect(fan.percent(forRPM: 1500) == 0)
        #expect(fan.percent(forRPM: 9000) == 100)
        #expect(FanRange(minRPM: 2000, maxRPM: 2000).percent(forRPM: 2500) == 0)
    }

    @Test func aUsableRangeIsPositiveRisingAndPlausible() {
        #expect(fan.isUsable)
        #expect(ranges.allSatisfy { $0.isUsable })
        let unusable = [FanRange(minRPM: 0, maxRPM: 5400), FanRange(minRPM: 2000, maxRPM: 2000),
                        FanRange(minRPM: 5400, maxRPM: 2000), FanRange(minRPM: 2000, maxRPM: .infinity),
                        FanRange(minRPM: 2000, maxRPM: 3.4e38), FanRange(minRPM: .nan, maxRPM: 5400),
                        FanRange(minRPM: 2000, maxRPM: .nan)]
        for range in unusable {
            #expect(!range.isUsable, "\(range)")
        }
    }

    @Test func theFasterFanWins() {
        let value = FanRange.fasterPercent(rpm: [3726, 3800], ranges: ranges)  // 50% and 60%
        #expect(abs((value ?? 0) - 60) < 0.01)
    }

    @Test func unusableReadingsCountAsMissing() {
        #expect(FanRange.fasterPercent(rpm: [nil, .nan], ranges: ranges) == nil)
        #expect(abs((FanRange.fasterPercent(rpm: [.infinity, 3800], ranges: ranges) ?? 0) - 60) < 0.01)
        #expect(FanRange.fasterPercent(rpm: [], ranges: ranges) == nil)
    }
}
