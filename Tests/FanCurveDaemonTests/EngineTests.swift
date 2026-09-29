import FanCurveCore
import Foundation
import Testing
@testable import FanCurveDaemon

/// A daemon wired to fakes, with its files in a scratch directory.
final class Harness {
    /// Idle, Radeon asleep (PG0R below 1 W): every curve asks for 0%.
    static let idle: [String: Double] = ["TC0F": 50, "PG0R": 0.1, "PC0R": 8, "F0Ac": 1800, "F1Ac": 1700]

    let dir: URL
    let paths: DaemonPaths
    let sensors = FakeSensors(Harness.idle)
    let actuator = FakeActuator()
    let checks = FakeChecks()
    let gpuSwitch = FakeGPUSwitch(GPUSwitchValues(ac: 2, battery: 2))
    var logs: [String] = []

    init() throws {
        dir = try makeTempDir()
        paths = DaemonPaths.rooted(at: dir)
        try paths.prepare()
    }

    deinit {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeEngine() -> Engine {
        Engine(profile: .macBookPro16_1, paths: paths, sensors: sensors, actuator: actuator, checks: checks,
               gpuPolicy: GPUPolicy(control: gpuSwitch), log: { [weak self] in self?.logs.append($0) })
    }

    /// Started and one tick in: active, holding the fans at 0% (1800 / 1700 rpm).
    func activeEngine() -> Engine {
        let engine = makeEngine()
        engine.start(now: 0, wall: 1000)
        engine.tick(now: 0.5, wall: 1000.5)
        actuator.calls.removeAll()
        return engine
    }
}

@Suite struct EngineTests {
    @Test func startReleasesThenTheFirstTickTakesControl() throws {
        let h = try Harness()
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        #expect(h.actuator.calls == ["release"])
        #expect(engine.mode == .starting)
        engine.tick(now: 0.5, wall: 1000.5)
        #expect(engine.mode == .active)
        #expect(h.actuator.calls == ["release", "take", "apply [1800, 1700]"])
    }

    @Test func theFirstRunSavesTheStockRangesFromTheSMC() throws {
        let h = try Harness()
        h.makeEngine().start(now: 0, wall: 1000)
        #expect(h.checks.rangeReads == 1)
        #expect(StateStore(url: h.paths.state).load().state.fans == h.checks.ranges)
        let again = h.makeEngine()
        again.start(now: 0, wall: 1100)
        #expect(h.checks.rangeReads == 1)
        #expect(again.fans == h.checks.ranges)
    }

    @Test func aWrongModelIsSafeAndNeverTouchesTheSMC() throws {
        let h = try Harness()
        h.checks.model = "MacBookPro18,1"
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        engine.tick(now: 0.5, wall: 1000.5)
        #expect(engine.mode == .safe(.unsupportedModel))
        #expect(h.actuator.calls.isEmpty)
    }

    @Test func aMissingFanKeyIsSafeButTheFansAreStillReleased() throws {
        let h = try Harness()
        h.checks.missing = ["F1Tg"]
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        #expect(engine.mode == .safe(.missingKeys))
        #expect(h.actuator.calls == ["release"])
    }

    @Test func theFifthStartInAMinuteIsACrashLoop() throws {
        let h = try Harness()
        try StateStore(url: h.paths.state).save(DaemonState(fans: h.checks.ranges, starts: [960, 970, 980, 990]))
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        #expect(engine.mode == .safe(.crashLoop))
        #expect(h.actuator.calls == ["release"])
        #expect(StateStore(url: h.paths.state).load().state.starts == [960, 970, 980, 990, 1000])
        engine.retry(now: 1)
        #expect(engine.mode == .starting)
    }

    @Test func aFailedApplyIsWrittenAgainOnTheNextTick() throws {
        let h = try Harness()
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        h.actuator.failApply = true
        engine.tick(now: 0.5, wall: 1000.5)
        h.actuator.failApply = false
        h.actuator.calls.removeAll()
        engine.tick(now: 1.0, wall: 1001)
        #expect(h.actuator.calls == ["take", "apply [1800, 1700]"])
        #expect(engine.snapshot(now: 1.0, wall: 1001).smcError == "SMC error 0x86")
        #expect(engine.snapshot(now: 11.0, wall: 1011).smcError == nil)
    }

    @Test func aTargetThatDidNotStickIsReassertedAfterTheDelay() throws {
        let h = try Harness()
        let engine = h.activeEngine()  // last write at now = 0.5
        h.actuator.verifyResult = false
        engine.tick(now: 1.0, wall: 1001)
        #expect(h.actuator.calls.isEmpty)
        engine.tick(now: 2.0, wall: 1002)
        #expect(h.actuator.calls == ["verify", "take", "apply [1800, 1700]"])
    }

    @Test func aHealthyReadbackWritesNothing() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        engine.tick(now: 2.0, wall: 1002)
        #expect(h.actuator.calls == ["verify"])
    }

    @Test func sleepReleasesAndWakeTakesBackAfterThePause() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        engine.willSleep(now: 1)
        #expect(engine.mode == .released(.sleep))
        #expect(h.actuator.calls == ["release"])
        engine.didWake(now: 2)
        engine.tick(now: 2.5, wall: 5000)
        #expect(engine.mode == .released(.sleep))
        engine.tick(now: 7.0, wall: 5004.5)
        #expect(engine.mode == .active)
        #expect(h.actuator.calls == ["release", "take", "apply [1800, 1700]"])
    }

    @Test func shutdownReleasesWhateverTheMode() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        engine.shutdown(now: 1)
        #expect(h.actuator.calls == ["release"])
    }

    @Test func historyKeepsOneRawSamplePerSecond() throws {
        let h = try Harness()
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        for step in 0..<5 {
            engine.tick(now: Double(step) * 0.5, wall: 1000 + Double(step) * 0.5)
        }
        #expect(engine.history(seconds: 60).map(\.t) == [1000, 1001, 1002])
        #expect(engine.history(seconds: 2).map(\.t) == [1001, 1002])
        #expect(engine.history(seconds: 60).last?.cpu == 50)
        #expect(engine.history(seconds: 60).last?.gpu == nil)
    }

    @Test func everyTickTouchesTheHeartbeat() throws {
        let h = try Harness()
        let engine = h.makeEngine()
        #expect(Heartbeat.age(h.paths.heartbeat) == nil)
        engine.start(now: 0, wall: 1000)
        engine.tick(now: 0, wall: 1000)
        #expect(try #require(Heartbeat.age(h.paths.heartbeat)) < 2)
    }

    @Test func aNaNTachometerNeitherCrashesNorBreaksStatus() throws {
        let h = try Harness()
        h.sensors.values["F0Ac"] = .nan
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        engine.tick(now: 0.5, wall: 1000.5)
        engine.tick(now: 1.0, wall: 1001)
        engine.tick(now: 1.5, wall: 1001.5)
        // Neither may throw: a NaN tachometer must not reach the takeover percent, where it would
        // trap `Int(...)` in FanRange.rpm(forPercent:) or fail to encode.
        _ = try LineCodec.encode(engine.snapshot(now: 1.5, wall: 1001.5))
        _ = try LineCodec.encode(engine.history(seconds: 60))
    }

    @Test func setConfigTakesCurvesAndSmoothingOnly() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        var requested = Config.defaults
        requested.enabled = false  // setEnabled owns this switch
        requested.curves.hotspot = Curve([CurvePoint(50, 10), CurvePoint(80, 100)])
        let applied = try engine.setConfig(requested)
        #expect(applied.enabled)
        #expect(applied.curves.hotspot == requested.curves.hotspot)
        #expect(ConfigStore(url: h.paths.config).load().config == applied)
    }

    @Test func anInvalidConfigChangesNothing() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        var requested = Config.defaults
        requested.curves.hotspot = Curve([CurvePoint(80, 50), CurvePoint(90, 10)])
        #expect(throws: ValidationError.self) { try engine.setConfig(requested) }
        #expect(engine.config == .defaults)
        #expect(!FileManager.default.fileExists(atPath: h.paths.config.path))
    }

    @Test func disablingHandsTheFansBackAndSurvivesARestart() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        try engine.setEnabled(false, now: 1)
        #expect(engine.mode == .disabled)
        #expect(h.actuator.calls == ["release"])
        #expect(ConfigStore(url: h.paths.config).load().config.enabled == false)
        let next = h.makeEngine()
        next.start(now: 0, wall: 1100)
        #expect(next.mode == .disabled)
    }

    @Test func switchingIsRefusedInSafeMode() throws {
        let h = try Harness()
        h.checks.model = "Other"
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        #expect(throws: ValidationError.self) { try engine.setEnabled(true, now: 1) }
    }

    @Test func autoGraphicsSavesTheOriginalsAndPutsThemBack() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        #expect(try engine.setGPUPolicy(true, now: 1) == GPUPolicyState(enabled: true, acSwitch: 1, batterySwitch: 2))
        #expect(StateStore(url: h.paths.state).load().state.gpuSwitchOriginal == GPUSwitchValues(ac: 2, battery: 2))
        #expect(engine.config.gpuPolicy.enabled)
        #expect(try engine.setGPUPolicy(false, now: 2) == GPUPolicyState(enabled: false, acSwitch: 2, batterySwitch: 2))
        #expect(!ConfigStore(url: h.paths.config).load().config.gpuPolicy.enabled)
    }

    @Test func snapshotReportsModeReadingsFansAndPolicy() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        let snapshot = engine.snapshot(now: 0.5, wall: 1000.5)
        #expect(snapshot.t == 1000.5)
        #expect(snapshot.mode == .active)
        #expect(snapshot.raw.cpu == 50)
        #expect(snapshot.demand.hotDie == .cpu)
        #expect(snapshot.fans == [
            FanState(actualRPM: 1800, targetRPM: 1800, minRPM: 1800, maxRPM: 5600),
            FanState(actualRPM: 1700, targetRPM: 1700, minRPM: 1700, maxRPM: 5200),
        ])
        #expect(snapshot.gpuPolicy == GPUPolicyState(enabled: false, acSwitch: 2, batterySwitch: 2))
        #expect(snapshot.configError == nil)
        #expect(snapshot.smcError == nil)
    }

    @Test func modeChangesAreLoggedOnce() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        engine.tick(now: 1.0, wall: 1001)
        #expect(h.logs.filter { $0.hasPrefix("mode:") } == ["mode: starting", "mode: active"])
    }

    // MARK: Owed releases, write-failure safe mode, GPU-policy ordering

    @Test func aReleaseThatFailsIsRetriedEveryTickAndWithholdsTheHeartbeat() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        h.actuator.failRelease = true
        h.sensors.values.removeValue(forKey: "TC0F")
        engine.tick(now: 1.0, wall: 1001)
        engine.tick(now: 1.5, wall: 1001.5)
        engine.tick(now: 2.0, wall: 1002)  // third missing tick: the channel is lost, mode releases
        #expect(engine.mode == .released(.sensorLoss))
        try FileManager.default.removeItem(at: h.paths.heartbeat)
        h.actuator.calls.removeAll()
        engine.tick(now: 2.5, wall: 1002.5)
        #expect(Heartbeat.age(h.paths.heartbeat) == nil)
        #expect(h.actuator.calls.contains("release"))
        h.actuator.failRelease = false
        h.actuator.calls.removeAll()
        engine.tick(now: 3.0, wall: 1003)
        #expect(h.actuator.calls.contains("release"))
        #expect(try #require(Heartbeat.age(h.paths.heartbeat)) < 2)
        h.actuator.calls.removeAll()
        engine.tick(now: 3.5, wall: 1003.5)
        #expect(!h.actuator.calls.contains("release"))
    }

    @Test func disablingRetriesAFailedRelease() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        h.actuator.failRelease = true
        try engine.setEnabled(false, now: 1)
        #expect(engine.mode == .disabled)
        h.actuator.failRelease = false
        h.actuator.calls.removeAll()
        engine.tick(now: 1.5, wall: 1001.5)
        #expect(h.actuator.calls.contains("release"))
    }

    @Test func persistentWriteFailuresHandTheFansBack() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        h.actuator.failApply = true
        h.sensors.values["TC0F"] = 100  // overheat: bypasses smoothing, an apply is due every tick
        engine.tick(now: 1.0, wall: 1001)
        engine.tick(now: 1.5, wall: 1001.5)
        engine.tick(now: 2.0, wall: 1002)  // third failed write in a row
        #expect(engine.mode == .safe(.smcWriteFailed))
        #expect(h.actuator.calls.contains("release"))
        #expect(engine.snapshot(now: 2.0, wall: 1002).smcError == "SMC error 0x86")
        h.actuator.failApply = false
        engine.retry(now: 2.5)
        #expect(engine.mode == .starting)
        engine.tick(now: 3.0, wall: 1003)
        #expect(engine.mode == .active)
    }

    @Test func everyTargetWriteReassertsForcedMode() throws {
        let h = try Harness()
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        h.actuator.failTakes = 1
        h.actuator.calls.removeAll()
        engine.tick(now: 0.5, wall: 1000.5)  // the take fails, so no target goes out
        engine.tick(now: 1.0, wall: 1001)    // the next tick writes it, forced mode first
        #expect(engine.mode == .active)
        #expect(h.actuator.calls == ["take", "take", "apply [1800, 1700]"])
        // A ramp: every target written on the way up goes out with forced mode in front of it, so a
        // mode the SMC dropped (sleep, the watchdog) never leaves a target unheeded.
        h.sensors.values["TC0F"] = 88
        for tick in 3...6 {
            engine.tick(now: Double(tick) * 0.5, wall: 1000 + Double(tick) * 0.5)
        }
        let applies = h.actuator.calls.indices.filter { h.actuator.calls[$0].hasPrefix("apply") }
        #expect(applies.count >= 3)
        #expect(applies.allSatisfy { h.actuator.calls[$0 - 1] == "take" })
    }

    @Test func aRejectedModeWriteEndsInSafeMode() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        h.actuator.failTakes = 100
        h.actuator.verifyResult = false
        var t = 1.0
        while engine.mode != .safe(.smcWriteFailed), t < 30 {
            engine.tick(now: t, wall: 1000 + t)
            t += 0.5
        }
        #expect(engine.mode == .safe(.smcWriteFailed))
        #expect(h.actuator.calls.contains("release"))
    }

    @Test func aHandBackResetsTheWriteFailureCount() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        h.actuator.failApply = true
        h.sensors.values["TC0F"] = 80  // move the target so a write is due
        var t = 1.0
        var failedApplies = 0
        while failedApplies < 2, t < 30 {
            h.actuator.calls.removeAll()
            engine.tick(now: t, wall: 1000 + t)
            failedApplies += h.actuator.calls.filter { $0.hasPrefix("apply") }.count
            t += 0.5
        }
        #expect(failedApplies == 2)
        #expect(engine.mode == .active)  // two failures, one short of the safe-mode threshold

        engine.willSleep(now: t)
        #expect(engine.mode == .released(.sleep))
        engine.didWake(now: t + 0.1)
        // The first take after the wake fails as well. Without the reset in releaseFans the streak
        // would reach 3 right here (2 before the sleep + this one) and the engine would enter safe
        // mode; a take that succeeded would reset the count by itself and prove nothing.
        h.actuator.failTakes = 1
        engine.tick(now: t + 0.1 + ControllerLimits.wakePauseSeconds + 0.5, wall: 2000)
        #expect(h.actuator.failTakes == 0)  // the failing take really ran
        #expect(engine.mode == .active)
    }

    @Test func autoGraphicsSavesTheOriginalsBeforeTheFirstPmsetWrite() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        h.gpuSwitch.failSets = true
        #expect(throws: GPUSwitchError.self) { try engine.setGPUPolicy(true, now: 1) }
        #expect(StateStore(url: h.paths.state).load().state.gpuSwitchOriginal == GPUSwitchValues(ac: 2, battery: 2))
        h.gpuSwitch.failSets = false
        h.gpuSwitch.values = .chargerDiscrete  // a half-applied pmset from the failed attempt above
        #expect(try engine.setGPUPolicy(true, now: 2) == GPUPolicyState(enabled: true, acSwitch: 1, batterySwitch: 2))
        #expect(StateStore(url: h.paths.state).load().state.gpuSwitchOriginal == GPUSwitchValues(ac: 2, battery: 2))
        #expect(try engine.setGPUPolicy(false, now: 3) == GPUPolicyState(enabled: false, acSwitch: 2, batterySwitch: 2))
        // The disable succeeded, so the originals are erased.
        #expect(StateStore(url: h.paths.state).load().state.gpuSwitchOriginal == nil)
    }

    @Test func autoGraphicsRefusesWhenTheOriginalsCannotBeRead() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        h.gpuSwitch.failReads = true
        #expect(throws: GPUSwitchError.self) { try engine.setGPUPolicy(true, now: 1) }
        #expect(h.gpuSwitch.sets.isEmpty)
    }

    @Test(.enabled(if: getuid() != 0))  // root ignores the permission bits this test relies on
    func autoGraphicsRefusesWhenTheOriginalsCannotBeSaved() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: h.paths.supportDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.paths.supportDir.path) }
        #expect(throws: (any Error).self) { try engine.setGPUPolicy(true, now: 1) }
        #expect(h.gpuSwitch.sets.isEmpty)
    }

    @Test func switchingAutoGraphicsOffForgetsTheOriginals() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        _ = try engine.setGPUPolicy(true, now: 1)
        #expect(StateStore(url: h.paths.state).load().state.gpuSwitchOriginal == GPUSwitchValues(ac: 2, battery: 2))
        _ = try engine.setGPUPolicy(false, now: 2)
        #expect(StateStore(url: h.paths.state).load().state.gpuSwitchOriginal == nil)
        #expect(h.gpuSwitch.values == GPUSwitchValues(ac: 2, battery: 2))

        // A choice made after auto-graphics was switched off (here modeled as the fake's values
        // simply being different) must not later be reverted by a stale, half-forgotten original.
        h.gpuSwitch.values = GPUSwitchValues(ac: 0, battery: 2)
        _ = try engine.setGPUPolicy(true, now: 3)
        #expect(StateStore(url: h.paths.state).load().state.gpuSwitchOriginal == GPUSwitchValues(ac: 0, battery: 2))
        _ = try engine.setGPUPolicy(false, now: 4)
        #expect(h.gpuSwitch.values == GPUSwitchValues(ac: 0, battery: 2))
        #expect(StateStore(url: h.paths.state).load().state.gpuSwitchOriginal == nil)
    }

    @Test(.enabled(if: getuid() != 0))  // root ignores the permission bits this test relies on
    func disablingHandsTheFansBackEvenIfTheConfigCannotBeSaved() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: h.paths.supportDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.paths.supportDir.path) }
        #expect(throws: (any Error).self) { try engine.setEnabled(false, now: 1) }
        #expect(h.actuator.calls.contains("release"))
        #expect(engine.mode == .disabled)
    }

    @Test func shutdownNeverWritesOnAnUnsupportedModel() throws {
        let h = try Harness()
        h.checks.model = "Other"
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        engine.shutdown(now: 1)
        #expect(h.actuator.calls.isEmpty)
    }

    @Test func shutdownReportsAFailedHandBack() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        h.actuator.failRelease = true
        engine.shutdown(now: 1)
        #expect(h.logs.last == "shutting down, but the fans could not be handed back; the watchdog will retry")
    }

    @Test func aFailedStartupReleaseWithholdsTheHeartbeat() throws {
        let h = try Harness()
        h.actuator.failRelease = true
        h.actuator.failTakes = 100  // the SMC refuses every write
        let engine = h.makeEngine()
        engine.start(now: 0, wall: 1000)
        #expect(h.actuator.calls == ["release", "release"])
        engine.tick(now: 0.5, wall: 1000.5)
        #expect(Heartbeat.age(h.paths.heartbeat) == nil)  // so the watchdog, with its own SMC connection, tries too
    }

    @Test func aTickBeforeStartDoesNothing() throws {
        let h = try Harness()
        let engine = h.makeEngine()
        engine.tick(now: 0, wall: 1000)
        #expect(h.actuator.calls.isEmpty)
        #expect(engine.mode == .starting)
        #expect(Heartbeat.age(h.paths.heartbeat) == nil)
    }

    @Test func retryOutsideSafeModeIsANoOp() throws {
        let h = try Harness()
        let engine = h.activeEngine()
        engine.retry(now: 1)
        #expect(engine.mode == .active)
        #expect(h.actuator.calls.isEmpty)
    }

    @Test func badStoredFanRangesAreReadAgain() throws {
        // A stored fan-range count that does not match the profile's is never trusted.
        let bad = try Harness()
        try StateStore(url: bad.paths.state).save(DaemonState(fans: [FanRange(minRPM: 1800, maxRPM: 5600)]))
        let engine = bad.makeEngine()
        engine.start(now: 0, wall: 1000)
        #expect(bad.checks.rangeReads == 1)
        #expect(engine.fans == bad.checks.ranges)

        // An unreadable SMC on a first run falls back to the profile ranges without persisting them.
        let noStock = try Harness()
        noStock.checks.ranges = nil
        let freshEngine = noStock.makeEngine()
        freshEngine.start(now: 0, wall: 1000)
        #expect(freshEngine.fans == HardwareProfile.macBookPro16_1.fans)
        #expect(StateStore(url: noStock.paths.state).load().state.fans == nil)
    }

    @Test func unusableStockRangesAreNotTrusted() throws {
        for ranges in [[FanRange(minRPM: 1800, maxRPM: 3.4e38), FanRange(minRPM: 1700, maxRPM: 5200)],
                       [FanRange(minRPM: 5600, maxRPM: 1800), FanRange(minRPM: 1700, maxRPM: 5200)]] {
            let h = try Harness()
            h.checks.ranges = ranges
            let engine = h.makeEngine()
            engine.start(now: 0, wall: 1000)
            #expect(engine.fans == HardwareProfile.macBookPro16_1.fans)
            #expect(StateStore(url: h.paths.state).load().state.fans == nil)
        }
    }

    @Test func aBrokenConfigIsLoggedInEnglish() throws {
        let h = try Harness()
        try Data("{broken".utf8).write(to: h.paths.config)
        let engine = h.makeEngine()
        #expect(h.logs.contains { $0.hasPrefix("config.json could not be read") })
        #expect(engine.snapshot(now: 0, wall: 0).configError != nil)
    }

    @Test func aBrokenStateIsLogged() throws {
        let h = try Harness()
        try Data("[]".utf8).write(to: h.paths.state)
        _ = h.makeEngine()
        #expect(h.logs.contains { $0.hasPrefix("state.json could not be read") })
    }
}
