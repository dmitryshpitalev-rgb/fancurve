import Testing
@testable import FanCurveHardware

@Suite struct ForcedActuatorTests {
    func makeSMC() -> FakeSMC {
        FakeSMC(["F0Md": 0, "F1Md": 0, "F0Tg": 1836, "F1Tg": 1700])
    }

    func makeActuator(_ smc: FakeSMC) throws -> ForcedActuator {
        try ForcedActuator(smc: smc, modeKeys: ["F0Md", "F1Md"], targetKeys: ["F0Tg", "F1Tg"])
    }

    @Test func takeApplyReleaseWriteTheExpectedKeys() throws {
        let smc = makeSMC()
        let fans = try makeActuator(smc)
        try fans.take()
        try fans.apply(rpm: [3000, 2800])
        try fans.release()
        #expect(smc.writes == ["F0Md=1", "F1Md=1", "F0Tg=3000", "F1Tg=2800", "F0Md=0", "F1Md=0"])
    }

    @Test func verifyChecksModeAndTargetOfEveryFan() throws {
        let smc = makeSMC()
        let fans = try makeActuator(smc)
        #expect(!fans.verify(targetRPM: [3000, 2800]))
        try fans.take()
        try fans.apply(rpm: [3000, 2800])
        #expect(fans.verify(targetRPM: [3000, 2800]))
        smc.values["F1Md"] = 0  // the SMC dropped forced mode, as it does across sleep
        #expect(!fans.verify(targetRPM: [3000, 2800]))
    }

    @Test func verifyNoticesATargetThatDidNotStick() throws {
        let smc = makeSMC()
        smc.ignoredWrites = ["F0Tg"]
        let fans = try makeActuator(smc)
        try fans.take()
        try fans.apply(rpm: [3000, 2800])
        #expect(!fans.verify(targetRPM: [3000, 2800]))
    }

    @Test func verifyLooksUpKeyInfoOnFirstUseAndKeepsIt() throws {
        let smc = makeSMC()
        let fans = try makeActuator(smc)
        #expect(smc.keyInfoLookups == 0)  // not at init: a failed lookup there would cost the startup release
        try fans.take()
        try fans.apply(rpm: [3000, 2800])
        smc.values["F0Md"] = nil  // a transient lookup failure is not kept
        #expect(!fans.verify(targetRPM: [3000, 2800]))
        smc.values["F0Md"] = 1
        #expect(fans.verify(targetRPM: [3000, 2800]))
        #expect(fans.verify(targetRPM: [3000, 2800]))
        #expect(smc.keyInfoLookups == 5)  // the failed one, then each of the four keys once
    }

    @Test func releaseTriesEveryFanAndReportsTheFirstError() throws {
        let smc = makeSMC()
        smc.values["F0Md"] = 1
        smc.values["F1Md"] = 1
        smc.failingWrites = ["F0Md"]
        let fans = try makeActuator(smc)
        #expect(throws: SMCError.self) { try fans.release() }
        #expect(smc.values["F1Md"] == 0)
    }

    @Test func rejectsBadKeysAndCounts() throws {
        #expect(throws: ActuatorError.invalidKey("F0Mode")) {
            try ForcedActuator(smc: makeSMC(), modeKeys: ["F0Mode"], targetKeys: ["F0Tg"])
        }
        #expect(throws: ActuatorError.keyCountMismatch(modes: 2, targets: 1)) {
            try ForcedActuator(smc: makeSMC(), modeKeys: ["F0Md", "F1Md"], targetKeys: ["F0Tg"])
        }
        let fans = try makeActuator(makeSMC())
        #expect(throws: ActuatorError.fanCountMismatch(expected: 2, got: 1)) { try fans.apply(rpm: [3000]) }
    }
}
