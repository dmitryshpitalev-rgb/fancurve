import Testing
@testable import FanCurveHardware

@Suite struct SystemInfoTests {
    @Test func stockLimitsReadMinAndMaxPerFan() {
        let smc = FakeSMC(["F0Mn": 1836, "F0Mx": 5616, "F1Mn": 1700, "F1Mx": 5200])
        #expect(SystemInfo.stockFanLimits(smc: smc, count: 2) == [FanLimits(min: 1836, max: 5616), FanLimits(min: 1700, max: 5200)])
    }

    @Test func anUnreadableRangeIsNil() {
        #expect(SystemInfo.stockFanLimits(smc: FakeSMC(["F0Mn": 1836]), count: 1) == nil)
    }

    /// Judging a range is the daemon's job, with FanCurveCore's rule (EngineTests.unusableStockRangesAreNotTrusted).
    @Test func aNonsenseRangeIsReportedAsRead() {
        #expect(SystemInfo.stockFanLimits(smc: FakeSMC(["F0Mn": 5000, "F0Mx": 1000]), count: 1) == [FanLimits(min: 5000, max: 1000)])
    }

    @Test func hardwareModelIsReadable() {
        #expect(SystemInfo.hardwareModel()?.isEmpty == false)
    }
}
