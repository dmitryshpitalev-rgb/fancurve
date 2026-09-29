import Foundation
import Testing
@testable import FanCurveHardware

@Suite struct LiveSensorsTests {
    @Test func readsSMCKeysAndTheRadeonColumns() {
        let smc = FakeSMC(["TC0F": 71.5, "F0Ac": 1836])
        let sensors = LiveSensors(
            smc: smc,
            names: ["TC0F", "TXXX", "F0Ac", "ioreg.gpu.temp", "ioreg.gpu.power", "toolong"],
            gpuStats: { GPUStats(temperature: 57, power: 7.5) }
        )
        #expect(sensors.unavailable == ["TXXX", "toolong"])
        #expect(sensors.read() == ["TC0F": 71.5, "F0Ac": 1836, "ioreg.gpu.temp": 57, "ioreg.gpu.power": 7.5])
    }

    @Test func aSleepingRadeonLeavesItsColumnsOut() {
        let sensors = LiveSensors(smc: FakeSMC([:]), names: ["ioreg.gpu.temp"], gpuStats: { GPUStats() })
        #expect(sensors.read().isEmpty)
    }

    @Test func ioregIsNotQueriedWhenNoColumnNeedsIt() {
        var queried = false
        let sensors = LiveSensors(smc: FakeSMC(["TC0F": 60]), names: ["TC0F"], gpuStats: {
            queried = true
            return GPUStats()
        })
        _ = sensors.read()
        #expect(!queried)
    }

    /// Run with: FANCURVE_HW_TESTS=1 swift test --filter LiveSensorsTests
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FANCURVE_HW_TESTS"] == "1"))
    func readsTheRealMachineWithoutRoot() throws {
        let sensors = LiveSensors(smc: try SMCClient(), names: ["TC0F", "F0Ac", "PC0R", "ioreg.gpu.temp"])
        #expect(sensors.unavailable.isEmpty)
        let values = sensors.read()
        #expect((values["TC0F"] ?? 0) > 20)
        #expect((values["F0Ac"] ?? 0) > 1000)
    }
}
