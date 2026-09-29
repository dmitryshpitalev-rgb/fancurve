import Testing
@testable import FanCurveCore

@Suite struct ControllerTests {
    static let fans = [FanRange(minRPM: 2000, maxRPM: 5400), FanRange(minRPM: 2000, maxRPM: 5400)]

    func makeController(enabled: Bool = true, smoothing: Smoothing = Smoothing()) -> Controller {
        var config = Config.defaults
        config.enabled = enabled
        config.smoothing = smoothing
        var controller = Controller(config: config, fans: Self.fans)
        _ = controller.startup(.ok)
        return controller
    }

    /// Idle-ish defaults: every curve evaluates to 0%.
    func input(_ time: Double, cpu: Double? = 50, gpu: Double? = 55, chassis: Double? = 33, power: Double? = 12,
               gpuActive: Bool = true, fanRPM: [Double?] = [2000, 2000]) -> TickInput {
        TickInput(time: time, channels: PerChannel(cpu: cpu, gpu: gpu, chassis: chassis, power: power),
                  gpuActive: gpuActive, fanRPM: fanRPM)
    }

    @Test func modeLabels() {
        #expect(Mode.active.label == "active")
        #expect(Mode.starting.label == "starting")
        #expect(Mode.disabled.label == "disabled")
        #expect(Mode.released(.sleep).label == "released:sleep")
        #expect(Mode.safe(.crashLoop).label == "safe:crashLoop")
    }

    @Test func takesControlAtCurrentFanSpeed() {
        var controller = makeController()
        let output = controller.tick(input(0, fanRPM: [3700, 3500]))
        #expect(output.mode == .active)
        #expect(output.actions == [.apply([3700, 3700])])
        #expect(output.outputPercent == 50)
    }

    /// Every way into control (the first tick, re-enabling, the end of a wake pause, recovery from a
    /// sensor loss) is a single `.apply`: the daemon forces the fans' mode with every target it
    /// writes, so the first target takes them.
    @Test func everyTakeoverIsOneApply() {
        let idle: [ActuatorAction] = [.apply([2000, 2000])]
        var controller = makeController()
        #expect(controller.tick(input(0)).actions == idle)
        _ = controller.setEnabled(false)
        _ = controller.setEnabled(true)
        #expect(controller.tick(input(0.5)).actions == idle)
        _ = controller.willSleep()
        controller.didWake(at: 10)
        #expect(controller.tick(input(15)).actions == idle)
        for time in [15.5, 16.0, 16.5] {
            _ = controller.tick(input(time, cpu: nil))
        }
        _ = controller.tick(input(17))
        #expect(controller.tick(input(27)).actions == idle)
    }

    @Test func startupWaitsForSensorsThenReleases() {
        var controller = makeController()
        #expect(controller.tick(input(0, cpu: nil)).mode == .starting)
        #expect(controller.tick(input(2.5, cpu: nil)).mode == .starting)
        let output = controller.tick(input(3.0, cpu: nil))
        #expect(output.mode == .released(.sensorLoss))
        #expect(output.actions.isEmpty)
    }

    @Test func releasesAfterThreeMissingCPUTicks() {
        var controller = makeController()
        _ = controller.tick(input(0))
        #expect(controller.tick(input(0.5, cpu: nil)).mode == .active)
        #expect(controller.tick(input(1.0, cpu: nil)).mode == .active)
        let lost = controller.tick(input(1.5, cpu: nil))
        #expect(lost.mode == .released(.sensorLoss))
        #expect(lost.actions == [.release])
    }

    @Test func recoversAfterTenSecondsOfValidData() {
        var controller = makeController()
        _ = controller.tick(input(0))
        for time in [0.5, 1.0, 1.5] {
            _ = controller.tick(input(time, cpu: nil))
        }
        #expect(controller.mode == .released(.sensorLoss))
        _ = controller.tick(input(2.0))
        #expect(controller.tick(input(11.5)).mode == .released(.sensorLoss))
        let back = controller.tick(input(12.0))
        #expect(back.mode == .active)
        #expect(back.actions == [.apply([2000, 2000])])
    }

    @Test func missingGPUIsIgnoredWhileRadeonIsOff() {
        var controller = makeController()
        _ = controller.tick(input(0))
        for tick in 1...10 {
            let output = controller.tick(input(Double(tick) * 0.5, gpu: nil, gpuActive: false))
            #expect(output.mode == .active)
            #expect(output.filtered.gpu == nil)
        }
    }

    @Test func missingGPUReleasesWhileRadeonIsOn() {
        var controller = makeController()
        _ = controller.tick(input(0))
        _ = controller.tick(input(0.5, gpu: nil))
        _ = controller.tick(input(1.0, gpu: nil))
        #expect(controller.tick(input(1.5, gpu: nil)).mode == .released(.sensorLoss))
    }

    @Test func overheatJumpsToFullSpeed() {
        var controller = makeController()
        _ = controller.tick(input(0))
        let hot = controller.tick(input(0.5, cpu: 96))
        #expect(hot.outputPercent == 100)
        #expect(hot.actions == [.apply([5400, 5400])])
    }

    @Test func radeonOverheatJumpsToFullSpeed() {
        var controller = makeController()
        _ = controller.tick(input(0))
        let hot = controller.tick(input(0.5, gpu: 96))
        #expect(hot.outputPercent == 100)
        #expect(hot.actions == [.apply([5400, 5400])])
    }

    @Test func overheatRestartsTheHold() {
        var controller = makeController()
        _ = controller.tick(input(0))
        _ = controller.tick(input(0.5, cpu: 96))
        #expect(controller.tick(input(20.0)).outputPercent == 100)
        #expect(controller.tick(input(21.0)).outputPercent == 98)
    }

    @Test func overheatOnInactiveRadeonIsIgnored() {
        var controller = makeController()
        _ = controller.tick(input(0))
        #expect(controller.tick(input(0.5, gpu: 99, gpuActive: false)).outputPercent == 0)
    }

    @Test func risesAtUpRateTowardDemand() {
        var controller = makeController()
        #expect(controller.tick(input(0, cpu: 88)).actions == [.apply([2000, 2000])])
        let step = controller.tick(input(0.5, cpu: 88))
        #expect(step.outputPercent == 12.5)
        #expect(step.actions == [.apply([2425, 2425])])
        #expect(step.demand.leading == .hotspot)
        #expect(step.demand.hotDie == .cpu)
        #expect(controller.tick(input(1.0, cpu: 88)).outputPercent == 25)
    }

    @Test func skipsWritesInsideDeadband() {
        var controller = makeController(smoothing: Smoothing(upPercentPerSecond: 2))
        _ = controller.tick(input(0, cpu: 88))
        #expect(controller.tick(input(0.5, cpu: 88)).actions.isEmpty)
        #expect(controller.tick(input(1.0, cpu: 88)).actions.isEmpty)
        let written = controller.tick(input(1.5, cpu: 88))
        #expect(written.actions == [.apply([2102, 2102])])
        #expect(written.targetRPM == [2102, 2102])
    }

    @Test func invalidateLastWriteForcesReapplyOfSameTarget() {
        var controller = makeController()
        let taken = controller.tick(input(0))
        #expect(taken.actions == [.apply([2000, 2000])])
        let steady = controller.tick(input(0.5))
        #expect(steady.actions.isEmpty)
        #expect(steady.targetRPM == [2000, 2000])
        controller.invalidateLastWrite()
        let reapplied = controller.tick(input(1.0))
        #expect(reapplied.actions == [.apply([2000, 2000])])
        #expect(reapplied.targetRPM == [2000, 2000])
    }

    @Test func disableReleasesAndEnableRetakes() {
        var controller = makeController()
        _ = controller.tick(input(0))
        #expect(controller.setEnabled(false) == [.release])
        #expect(controller.mode == .disabled)
        #expect(controller.config.enabled == false)
        #expect(controller.tick(input(0.5)).actions.isEmpty)
        #expect(controller.setEnabled(true).isEmpty)
        #expect(controller.tick(input(1.0)).actions == [.apply([2000, 2000])])
    }

    @Test func startsDisabledWhenConfigSaysSo() {
        var controller = makeController(enabled: false)
        #expect(controller.mode == .disabled)
        #expect(controller.tick(input(0)).actions.isEmpty)
    }

    @Test func safeModeNeverTakesControlUntilStartupSucceeds() {
        var controller = Controller(config: .defaults, fans: Self.fans)
        _ = controller.startup(.failed(.crashLoop))
        #expect(controller.mode == .safe(.crashLoop))
        #expect(controller.tick(input(0)).actions.isEmpty)
        #expect(controller.setEnabled(true).isEmpty)
        #expect(controller.mode == .safe(.crashLoop))
        _ = controller.startup(.ok)
        #expect(controller.tick(input(1)).mode == .active)
    }

    @Test func setEnabledDoesNotPersistInSafeMode() {
        var controller = Controller(config: .defaults, fans: Self.fans)
        _ = controller.startup(.failed(.crashLoop))
        #expect(controller.config.enabled == true)
        #expect(controller.setEnabled(false).isEmpty)
        #expect(controller.config.enabled == true)
    }

    @Test func startupFailureWhileActiveReleases() {
        var controller = makeController()
        _ = controller.tick(input(0))
        #expect(controller.startup(.failed(.missingKeys)) == [.release])
        #expect(controller.mode == .safe(.missingKeys))
    }

    @Test func sleepReleasesAndWakeRetakesAfterPause() {
        var controller = makeController()
        _ = controller.tick(input(0))
        #expect(controller.willSleep() == [.release])
        #expect(controller.mode == .released(.sleep))
        controller.didWake(at: 100)
        #expect(controller.tick(input(102)).mode == .released(.sleep))
        let back = controller.tick(input(105))
        #expect(back.mode == .active)
        #expect(back.actions == [.apply([2000, 2000])])
    }

    @Test func wakeWhileActiveReleasesAndRetakesAfterPause() {
        var controller = makeController()
        _ = controller.tick(input(0))
        controller.didWake(at: 100)
        #expect(controller.mode == .released(.sleep))
        #expect(controller.tick(input(102)).mode == .released(.sleep))
        let back = controller.tick(input(105))
        #expect(back.mode == .active)
        #expect(back.actions == [.apply([2000, 2000])])
    }

    @Test func sleepDoesNotTouchDisabledMode() {
        var controller = makeController(enabled: false)
        #expect(controller.willSleep().isEmpty)
        controller.didWake(at: 10)
        #expect(controller.mode == .disabled)
    }

    @Test func setConfigValidatesAndKeepsEnabledFlag() throws {
        var controller = makeController(enabled: false)
        var new = Config.defaults
        new.enabled = true
        new.smoothing.holdSeconds = 5
        try controller.setConfig(new)
        #expect(controller.config.smoothing.holdSeconds == 5)
        #expect(controller.config.enabled == false)
        new.curves.hotspot = Curve([CurvePoint(90, 50), CurvePoint(80, 60)])
        #expect(throws: ValidationError.self) { try controller.setConfig(new) }
    }

    @Test func radeonComingBackOnlineKeepsTheThreeTickGrace() {
        var controller = makeController()
        _ = controller.tick(input(0, gpu: nil, gpuActive: false))
        #expect(controller.tick(input(0.5, gpu: nil)).mode == .active)
        #expect(controller.tick(input(1.0, gpu: nil)).mode == .active)
        #expect(controller.tick(input(1.5, gpu: nil)).mode == .released(.sensorLoss))
    }

    @Test func flappingGPUActiveWithMissingTemperatureEventuallyReleases() {
        var controller = makeController()
        // gpuActive flips every single tick and the gpu temperature never reads, from tick 0.
        var mode: Mode = .starting
        for tick in 0...20 {
            let active = tick.isMultiple(of: 2)
            mode = controller.tick(input(Double(tick) * 0.5, gpu: nil, gpuActive: active)).mode
            if mode == .released(.sensorLoss) { break }
        }
        #expect(mode == .released(.sensorLoss))
    }

    /// No usable tachometer reading, missing or not finite: control starts at 100%, the loud side.
    @Test func takeoverWithoutTachometerStartsAtFullSpeed() {
        for readings: [Double?] in [[nil, nil], [.nan, .nan], [.infinity, nil]] {
            var controller = makeController()
            let output = controller.tick(input(0, fanRPM: readings))
            #expect(output.mode == .active)
            #expect(output.outputPercent == 100)
            #expect(output.actions == [.apply([5400, 5400])])
        }
    }

    @Test func aFiniteFanStillSetsTheTakeoverSpeed() {
        var controller = makeController()
        let output = controller.tick(input(0, fanRPM: [.nan, 3700]))
        #expect(output.outputPercent == 50)
        #expect(output.actions == [.apply([3700, 3700])])
    }

    /// A Radeon that goes back to sleep must not leave a stale filtered GPU value behind for the
    /// next wake to resurrect: it should read as absent (and drive no demand) until three real
    /// misses accumulate, same as any other channel loss.
    @Test func radeonReactivationAfterSleepDoesNotResurrectAStaleGPUReading() {
        var controller = makeController()
        _ = controller.tick(input(0, gpu: 88))
        for tick in 1...120 {
            _ = controller.tick(input(Double(tick) * 0.5, gpu: nil, gpuActive: false))
        }
        let wake1 = controller.tick(input(60.5, gpu: nil))
        let wake2 = controller.tick(input(61.0, gpu: nil))
        let wake3 = controller.tick(input(61.5, gpu: nil))
        #expect(wake1.filtered.gpu == nil)
        #expect(wake2.filtered.gpu == nil)
        #expect(wake1.demand.hotDie == .cpu)
        #expect(wake2.demand.hotDie == .cpu)
        #expect(wake1.mode == .active)
        #expect(wake2.mode == .active)
        #expect(wake3.mode == .released(.sensorLoss))
    }

    /// A wake resume must not take control on a GPU value that is only stale (held from before a
    /// sleep-time nap of the Radeon, never actually refreshed after the wake pause).
    @Test func wakeResumeDoesNotTakeControlOnAStaleGPUValue() {
        var controller = makeController()
        _ = controller.tick(input(0))
        #expect(controller.willSleep() == [.release])
        controller.didWake(at: 100)
        _ = controller.tick(input(100.5, gpu: 60))
        for tick in 1...8 {
            _ = controller.tick(input(100.5 + Double(tick) * 0.5, gpu: nil, gpuActive: false))
        }
        let resumed = controller.tick(input(105.0, gpu: nil))
        #expect(resumed.actions.isEmpty)
        #expect(resumed.mode == .released(.sensorLoss))
    }

    /// The 95°C bypass applies on the very tick that takes control.
    @Test func overheatOnTheTakeTickCommandsFullSpeedImmediately() {
        var controller = makeController()
        let output = controller.tick(input(0, cpu: 96))
        #expect(output.actions == [.apply([5400, 5400])])
    }

    /// A bare wake (no willSleep) leaves `hasControl` true; if sensors still aren't ready when the
    /// wake pause ends, the resume tick must hand control back to macOS explicitly rather than only
    /// updating internal mode.
    @Test func bareWakeThenResumeWithSensorsNotReadyEmitsRelease() {
        var controller = makeController()
        _ = controller.tick(input(0))
        controller.didWake(at: 100)
        for tick in stride(from: 100.5, to: 105.0, by: 0.5) {
            #expect(controller.tick(input(tick, cpu: nil)).mode == .released(.sleep))
        }
        let resumed = controller.tick(input(105.0, cpu: nil))
        #expect(resumed.actions == [.release])
        #expect(resumed.mode == .released(.sensorLoss))
    }
}
