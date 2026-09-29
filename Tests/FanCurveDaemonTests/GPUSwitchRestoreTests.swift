import Testing
@testable import FanCurveDaemon

@Suite struct GPUSwitchRestoreTests {
    @Test func savedValuesAreRestored() {
        let saved = GPUSwitchValues(ac: 2, battery: 2)
        #expect(GPUSwitchRestore.decide(gpuPolicyEnabled: true, saved: saved) == .restore(saved))
        #expect(GPUSwitchRestore.decide(gpuPolicyEnabled: false, saved: saved) == .restore(saved))
    }

    @Test func nothingSavedWithAutoGraphicsOffLeavesTheUsersChoice() {
        #expect(GPUSwitchRestore.decide(gpuPolicyEnabled: false, saved: nil) == .untouched)
    }

    @Test func nothingSavedWhileAutoGraphicsIsOnIsReported() {
        #expect(GPUSwitchRestore.decide(gpuPolicyEnabled: true, saved: nil) == .lost)
    }
}
