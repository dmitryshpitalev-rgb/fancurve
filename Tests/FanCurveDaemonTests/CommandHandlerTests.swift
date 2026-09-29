import FanCurveCore
import Foundation
import Testing
@testable import FanCurveDaemon

@Suite struct CommandHandlerTests {
    func line(_ id: Int, _ cmd: Command, _ args: RequestArgs? = nil) throws -> Data {
        var data = try LineCodec.encode(Request(id: id, cmd: cmd, args: args))
        data.removeLast()  // the server strips the newline before handing the line over
        return data
    }

    func handler(_ engine: Engine) -> CommandHandler {
        CommandHandler(engine: engine, clock: { (now: 0.5, wall: 1000.5) })
    }

    @Test func statusReturnsTheSnapshot() throws {
        let h = try Harness()
        let reply = handler(h.activeEngine()).handle(try line(7, .status))
        #expect(reply.last == 0x0A)
        let response = try LineCodec.decode(Response<Snapshot>.self, from: reply)
        #expect(response.id == 7)
        #expect(response.ok)
        #expect(response.data?.mode == .active)
    }

    @Test func historyChecksItsWindow() throws {
        let h = try Harness()
        let handler = handler(h.activeEngine())
        let bad = try LineCodec.decode(Response<[Sample]>.self, from: handler.handle(try line(1, .history, RequestArgs(seconds: 0))))
        #expect(!bad.ok)
        #expect(bad.error == "history: seconds must be 1 to \(HistoryLimits.seconds)")
        let tooLong = try LineCodec.decode(Response<[Sample]>.self,
                                           from: handler.handle(try line(3, .history, RequestArgs(seconds: HistoryLimits.seconds + 1))))
        #expect(!tooLong.ok)
        let good = try LineCodec.decode(Response<[Sample]>.self, from: handler.handle(try line(2, .history, RequestArgs(seconds: 60))))
        #expect(good.data?.count == 1)
    }

    @Test func getAndSetConfig() throws {
        let h = try Harness()
        let handler = handler(h.activeEngine())
        let current = try LineCodec.decode(Response<Config>.self, from: handler.handle(try line(1, .getConfig)))
        #expect(current.data == .defaults)
        var requested = Config.defaults
        requested.curves.hotspot = Curve([CurvePoint(55, 0), CurvePoint(85, 100)])
        let applied = try LineCodec.decode(Response<Config>.self, from: handler.handle(try line(2, .setConfig, RequestArgs(config: requested))))
        #expect(applied.data?.curves.hotspot == requested.curves.hotspot)
        requested.curves.hotspot = Curve([CurvePoint(80, 50), CurvePoint(90, 10)])
        let refused = try LineCodec.decode(Response<Config>.self, from: handler.handle(try line(3, .setConfig, RequestArgs(config: requested))))
        #expect(!refused.ok)
        #expect(refused.error == "hotspot: speed must not fall as x grows (point 2)")
    }

    @Test func setEnabledAnswersWithTheNewMode() throws {
        let h = try Harness()
        let reply = handler(h.activeEngine()).handle(try line(1, .setEnabled, RequestArgs(enabled: false)))
        #expect(try LineCodec.decode(Response<Snapshot>.self, from: reply).data?.mode == .disabled)
    }

    @Test func setGPUPolicyAnswersWithItsState() throws {
        let h = try Harness()
        let reply = handler(h.activeEngine()).handle(try line(1, .setGPUPolicy, RequestArgs(enabled: true)))
        #expect(try LineCodec.decode(Response<GPUPolicyState>.self, from: reply).data
            == GPUPolicyState(enabled: true, acSwitch: 1, batterySwitch: 2))
    }

    @Test func retryLeavesSafeMode() throws {
        let h = try Harness()
        h.checks.model = "Other"
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        #expect(engine.mode == .safe(.unsupportedModel))
        h.checks.model = "MacBookPro16,1"
        let reply = handler(engine).handle(try line(1, .retry))
        #expect(try LineCodec.decode(Response<Snapshot>.self, from: reply).data?.mode == .starting)
    }

    @Test func missingArgumentsAreExplained() throws {
        let h = try Harness()
        let reply = handler(h.activeEngine()).handle(try line(4, .setEnabled))
        let response = try LineCodec.decode(Response<EmptyData>.self, from: reply)
        #expect(response.id == 4)
        #expect(response.error == "setEnabled: no enabled argument")
    }

    @Test func garbageGetsAnErrorLine() throws {
        let h = try Harness()
        let reply = handler(h.activeEngine()).handle(Data("{not json".utf8))
        #expect(reply.last == 0x0A)
        let response = try LineCodec.decode(Response<EmptyData>.self, from: reply)
        #expect(!response.ok)
        #expect(response.error?.hasPrefix("bad request") == true)
    }

    @Test func systemErrorsGetALead() throws {
        let h = try Harness()
        h.gpuSwitch.failSets = true
        let reply = handler(h.activeEngine()).handle(try line(1, .setGPUPolicy, RequestArgs(enabled: true)))
        let response = try LineCodec.decode(Response<GPUPolicyState>.self, from: reply)
        #expect(!response.ok)
        #expect(response.error?.hasPrefix("could not switch graphics: ") == true)
    }

    @Test(.enabled(if: getuid() != 0))  // root ignores the permission bits this test relies on
    func aConfigThatCannotBeSavedGetsALead() throws {
        let h = try Harness()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: h.paths.supportDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.paths.supportDir.path)
        }
        let reply = handler(h.activeEngine()).handle(try line(1, .setConfig, RequestArgs(config: .defaults)))
        let response = try LineCodec.decode(Response<Config>.self, from: reply)
        #expect(!response.ok)
        #expect(response.error?.hasPrefix("could not apply the config: ") == true)
    }
}
