import FanCurveCore
import FanCurveHardware
import Testing

/// FanCurveCore cannot see FanCurveHardware, so the profile spells out the Radeon's column names;
/// they must be the ones LiveSensors fills.
@Suite struct ProfileColumnsTests {
    @Test func theProfileNamesTheRadeonColumnsLiveSensorsFills() {
        #expect(HardwareProfile.macBookPro16_1.gpuIoregTemp == LiveSensors.gpuTemperatureColumn)
        #expect(HardwareProfile.macBookPro16_1.gpuPower == LiveSensors.gpuPowerColumn)
    }
}
