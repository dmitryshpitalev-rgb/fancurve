import Testing
@testable import FanCurveDaemon

@Suite struct DaemonInvocationTests {
    @Test func eachModeParses() {
        #expect(DaemonInvocation.parse([]) == .daemon)
        #expect(DaemonInvocation.parse(["--watchdog"]) == .watchdog)
        #expect(DaemonInvocation.parse(["--restore"]) == .restore)
        #expect(DaemonInvocation.parse(["--dry-run", "--root", "/tmp/x"]) == .dryRun(root: "/tmp/x"))
        #expect(DaemonInvocation.parse(["--simulate", "t.csv", "--profile", "p.json"])
                == .simulate(trace: "t.csv", profile: "p.json", config: nil))
        #expect(DaemonInvocation.parse(["--simulate", "t.csv", "--config", "c.json", "--profile", "p.json"])
                == .simulate(trace: "t.csv", profile: "p.json", config: "c.json"))
    }

    @Test func mixedModesAreRejected() {
        // --restore must not win over --dry-run: that would make real writes.
        #expect(DaemonInvocation.parse(["--dry-run", "--root", "/tmp/x", "--restore"]) == nil)
        #expect(DaemonInvocation.parse(["--restore", "--dry-run"]) == nil)
        #expect(DaemonInvocation.parse(["--watchdog", "--restore"]) == nil)
        #expect(DaemonInvocation.parse(["--simulate", "t.csv", "--profile", "p.json", "--watchdog"]) == nil)
    }

    @Test func incompleteOrUnknownArgumentsAreRejected() {
        #expect(DaemonInvocation.parse(["--dry-run"]) == nil)
        #expect(DaemonInvocation.parse(["--dry-run", "--root"]) == nil)
        #expect(DaemonInvocation.parse(["--dry-run", "--root", "/tmp/x", "--root", "/tmp/y"]) == nil)
        #expect(DaemonInvocation.parse(["--root", "/tmp/x", "--dry-run"]) == nil)
        #expect(DaemonInvocation.parse(["--simulate"]) == nil)
        #expect(DaemonInvocation.parse(["--simulate", "t.csv"]) == nil)
        #expect(DaemonInvocation.parse(["--simulate", "--profile", "p.json"]) == nil)
        #expect(DaemonInvocation.parse(["--verbose"]) == nil)
    }
}
