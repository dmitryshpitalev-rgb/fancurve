import Foundation
import Testing
@testable import FanCurveCore

@Suite struct HardwareProfileTests {
    @Test func embeddedProfileMatchesTheMeasuredOne() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/FanCurveCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("docs/hardware-profile.json"))
        #expect(try JSONDecoder().decode(HardwareProfile.self, from: data) == HardwareProfile.macBookPro16_1)
    }

    @Test func columnNamesCoverEveryReadingOnce() {
        let names = HardwareProfile.macBookPro16_1.columnNames
        #expect(names.count == Set(names).count)
        #expect(names.count == 27)
        #expect(names.first == "TC0E")
        #expect(names.last == "F1Ac")
        for name in ["ioreg.gpu.temp", "ioreg.gpu.power", "PG0R", "PC0R", "Ts2S", "TGDF"] {
            #expect(names.contains(name))
        }
    }

    @Test func requiredFanKeysAreModeTargetAndTachometer() {
        #expect(HardwareProfile.macBookPro16_1.requiredFanKeys == ["F0Md", "F1Md", "F0Tg", "F1Tg", "F0Ac", "F1Ac"])
    }

    @Test func everyFanHasItsKeys() {
        let profile = HardwareProfile.macBookPro16_1
        #expect(profile.fanMode.count == profile.fans.count)
        #expect(profile.fanTarget.count == profile.fans.count)
        #expect(profile.fanActual.count == profile.fans.count)
    }
}
