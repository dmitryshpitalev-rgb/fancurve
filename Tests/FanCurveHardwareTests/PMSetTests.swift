import Foundation
import Testing
@testable import FanCurveHardware

@Suite struct PMSetTests {
    @Test func parsesBothPowerSources() {
        let text = "Battery Power:\n lidwake              1\n gpuswitch            2\nAC Power:\n gpuswitch            1\n sleep                1\n"
        let values = PMSet.parseGPUSwitch(text)
        #expect(values.ac == 1)
        #expect(values.battery == 2)
    }

    @Test func missingValuesAreNil() {
        let values = PMSet.parseGPUSwitch("AC Power:\n sleep 1\n")
        #expect(values.ac == nil)
        #expect(values.battery == nil)
    }

    /// A daemon calls pmset for days: descriptors must not leak. /usr/bin/true stands in for pmset,
    /// so this runs on any Mac; the bound leaves room for tests running alongside.
    @Test func callsDoNotLeakDescriptors() throws {
        func openDescriptors() -> Int {
            (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
        }
        let before = openDescriptors()
        for _ in 0..<100 {
            _ = try PMSet.run([], executable: "/usr/bin/true")
        }
        #expect(openDescriptors() - before < 50)
    }

    /// The real pmset, reads only; needs two GPUs and a battery.
    /// Run with: FANCURVE_HW_TESTS=1 swift test --filter PMSetTests
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FANCURVE_HW_TESTS"] == "1"))
    func readsTheLiveGPUSwitch() throws {
        let live = try PMSet.readGPUSwitch()
        #expect(live.ac != nil)
        #expect(live.battery != nil)
    }
}
