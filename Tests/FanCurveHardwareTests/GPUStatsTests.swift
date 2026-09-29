import Foundation
import Testing
@testable import FanCurveHardware

@Suite struct GPUStatsTests {
    @Test func parsesPerformanceStatistics() {
        let stats: [String: Any] = [
            "Temperature(C)": NSNumber(value: 58),
            "Total Power(W)": NSNumber(value: 8),
            "GPU Activity(%)": NSNumber(value: 5),
            "Fan Speed(RPM)": NSNumber(value: 0),
        ]
        #expect(GPUStatsReader.parsePerformanceStatistics(stats) == GPUStats(temperature: 58, power: 8, activity: 5))
    }

    @Test func missingFieldsAreNil() {
        #expect(GPUStatsReader.parsePerformanceStatistics([:]) == GPUStats())
    }
}
