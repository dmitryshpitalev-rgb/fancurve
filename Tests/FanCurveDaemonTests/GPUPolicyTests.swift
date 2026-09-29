import FanCurveCore
import Testing
@testable import FanCurveDaemon

@Suite struct GPUPolicyTests {
    let automatic = GPUSwitchValues(ac: 2, battery: 2)

    @Test func enablePutsTheRadeonOnTheCharger() throws {
        let control = FakeGPUSwitch(automatic)
        let policy = GPUPolicy(control: control)
        try policy.enable(now: 0)
        #expect(control.values == .chargerDiscrete)
        #expect(policy.state(enabled: true, now: 1) == GPUPolicyState(enabled: true, acSwitch: 1, batterySwitch: 2))
    }

    @Test func readCurrentReadsTheControlEveryTime() throws {
        let control = FakeGPUSwitch(automatic)
        let policy = GPUPolicy(control: control)
        #expect(try policy.readCurrent() == automatic)
        #expect(try policy.readCurrent() == automatic)
        #expect(control.reads == 2)
    }

    @Test func disableWritesTheOriginalsBack() throws {
        let control = FakeGPUSwitch(.chargerDiscrete)
        let policy = GPUPolicy(control: control)
        try policy.disable(savedOriginal: automatic, now: 0)
        #expect(control.values == automatic)
    }

    @Test func disableWithoutOriginalsTouchesNothing() throws {
        let control = FakeGPUSwitch(automatic)
        try GPUPolicy(control: control).disable(savedOriginal: nil, now: 0)
        #expect(control.sets.isEmpty)
    }

    @Test func whatWasWrittenIsReportedWithoutAnotherRead() throws {
        let control = FakeGPUSwitch(automatic)
        let policy = GPUPolicy(control: control)
        try policy.enable(now: 0)
        #expect(policy.current(now: 1) == .chargerDiscrete)
        try policy.disable(savedOriginal: automatic, now: 2)
        #expect(policy.current(now: 3) == automatic)
        #expect(control.reads == 0)
    }

    @Test func afterAFailedWriteTheNextLookReadsAgain() {
        let control = FakeGPUSwitch(automatic)
        let policy = GPUPolicy(control: control)
        _ = policy.current(now: 0)
        control.failSets = true
        #expect(throws: GPUSwitchError.self) { try policy.enable(now: 1) }
        #expect(control.reads == 1)
        _ = policy.current(now: 2)
        #expect(control.reads == 2)
    }

    @Test func currentValuesAreReadAtMostEveryThirtySeconds() {
        let control = FakeGPUSwitch(automatic)
        let policy = GPUPolicy(control: control)
        _ = policy.current(now: 0)
        _ = policy.current(now: 29)
        #expect(control.reads == 1)
        _ = policy.current(now: 30)
        #expect(control.reads == 2)
        #expect(policy.state(enabled: false, now: 31) == GPUPolicyState(enabled: false, acSwitch: 2, batterySwitch: 2))
    }
}
