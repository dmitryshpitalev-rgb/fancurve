import FanCurveCore
import Testing
@testable import FanCurveIPC

@Suite struct CtlTests {
    @Test func versionNeedsNoDaemon() throws {
        #expect(try Ctl.parse(["version"]).command == .version)
        #expect(try Ctl.parse(["--socket", "/tmp/x.sock", "version"]) == CtlInvocation(socketPath: "/tmp/x.sock", command: .version))
        #expect(Ctl.usage.contains("version"))
    }

    @Test func parsesEveryCommand() throws {
        #expect(try Ctl.parse(["status"]) == CtlInvocation(socketPath: DaemonSocket.path, command: .status(json: false)))
        #expect(try Ctl.parse(["status", "--json"]).command == .status(json: true))
        #expect(try Ctl.parse(["history"]).command == .history(seconds: 60))
        #expect(try Ctl.parse(["history", "300"]).command == .history(seconds: 300))
        #expect(try Ctl.parse(["config", "get"]).command == .configGet)
        #expect(try Ctl.parse(["config", "set", "my.json"]).command == .configSet(path: "my.json"))
        #expect(try Ctl.parse(["enable"]).command == .enable)
        #expect(try Ctl.parse(["disable"]).command == .disable)
        #expect(try Ctl.parse(["gpu", "on"]).command == .gpu(on: true))
        #expect(try Ctl.parse(["gpu", "off"]).command == .gpu(on: false))
        #expect(try Ctl.parse(["retry"]).command == .retry)
    }

    @Test func theSocketCanBeOverridden() throws {
        #expect(try Ctl.parse(["--socket", "/tmp/x.sock", "status"]).socketPath == "/tmp/x.sock")
    }

    @Test func rejectsNonsense() {
        let bad: [[String]] = [[], ["history", "0"], ["history", "\(HistoryLimits.seconds + 1)"], ["history", "abc"], ["gpu"],
                               ["config", "set"], ["--socket"], ["reboot"]]
        for arguments in bad {
            #expect(throws: CtlError.self) { try Ctl.parse(arguments) }
        }
    }
}
