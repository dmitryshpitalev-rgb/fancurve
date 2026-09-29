import Testing
@testable import FanCurveDaemon

@Suite struct HardwareChecksTests {
    @Test func missingKeysAreTheOnesTheSMCDoesNotKnow() {
        let checks = SMCHardwareChecks(smc: KeySetSMC(["F0Md", "F0Tg"]))
        #expect(checks.missingKeys(["F0Md", "F1Md", "F0Tg", "toolong"]) == ["F1Md", "toolong"])
        #expect(SMCHardwareChecks(smc: nil).missingKeys(["F0Md", "F0Tg"]) == ["F0Md", "F0Tg"])
    }
}
