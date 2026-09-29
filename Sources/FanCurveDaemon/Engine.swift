import FanCurveCore
import FanCurveHardware
import Foundation

/// The daemon's control loop around `FanCurveCore.Controller`: reads the sensors, executes the
/// controller's actuator actions, checks the SMC readback and re-asserts, keeps the history and
/// answers the socket commands. Not thread-safe: the daemon calls everything on one serial queue.
/// `now` is monotonic seconds; `wall` is Unix time (history, heartbeat, crash-loop starts).
public final class Engine {
    /// The tick period: `ControllerLimits.lossTicks`, `verifyDelaySeconds` and the history's one
    /// sample per second assume it.
    public static let tickSeconds = 0.5
    /// A readback right after a write still shows the old value (the SMC applies writes about a
    /// second later, traces/actuator-test.log), so the check waits this long after the last write.
    static let verifyDelaySeconds = 1.5
    static let historyCapacity = HistoryLimits.seconds
    /// How long a failed SMC write stays visible in the Snapshot.
    static let smcErrorHoldSeconds = 10.0

    let profile: HardwareProfile
    let paths: DaemonPaths
    private let sensors: SensorSource
    private let actuator: FanActuating
    private let checks: HardwareChecks
    private let gpuPolicy: GPUPolicy
    private let log: (String) -> Void
    private let configStore: ConfigStore
    private let stateStore: StateStore

    private(set) var config: Config
    private(set) var configError: String?
    private var state: DaemonState
    private var controller: Controller
    private var history = RingBuffer<Sample>(capacity: Engine.historyCapacity)
    private var lastOutput: TickOutput?
    private var lastFanRPM: [Double?] = []
    private var lastSampleSecond: Int?
    private var lastWriteAt: Double?
    private var lastSMCError: (message: String, at: Double)?
    private var loggedMode: Mode?

    /// Failed writes in a row at which the fans go back to macOS and the daemon enters
    /// safe(smcWriteFailed) until the user retries.
    static let maxConsecutiveWriteFailures = 3

    private var started = false
    private var consecutiveWriteFailures = 0
    /// A release failed twice: retried on every tick outside `.active`, heartbeat withheld meanwhile
    /// so the watchdog's own SMC connection retries too.
    private var releaseOwed = false
    private var logLimiter = LogLimiter()

    public init(profile: HardwareProfile, paths: DaemonPaths, sensors: SensorSource, actuator: FanActuating,
                checks: HardwareChecks, gpuPolicy: GPUPolicy, log: @escaping (String) -> Void) {
        self.profile = profile
        self.paths = paths
        self.sensors = sensors
        self.actuator = actuator
        self.checks = checks
        self.gpuPolicy = gpuPolicy
        self.log = log
        configStore = ConfigStore(url: paths.config)
        stateStore = StateStore(url: paths.state)
        let loadedConfig = configStore.load()
        let loadedState = stateStore.load()
        config = loadedConfig.config
        configError = loadedConfig.error
        state = loadedState.state
        controller = Controller(config: loadedConfig.config,
                                fans: Self.validFans(loadedState.state.fans, count: profile.fans.count) ?? profile.fans)
        if let error = loadedConfig.error { log(error) }
        if let error = loadedState.error { log(error) }
    }

    var mode: Mode { controller.mode }
    var fans: [FanRange] { controller.fans }

    // MARK: Lifecycle

    public func start(now: Double, wall: Double) {
        started = true
        guard checks.modelIdentifier() == profile.model else { return enterSafe(.unsupportedModel, now: now) }
        // Before the key checks: a predecessor may have died holding the fans, and a transient
        // key-info failure must not leave its forced mode in place.
        releaseFans(now: now)
        guard hardwareKeysPresent() else { return enterSafe(.missingKeys, now: now) }
        let fanCount = profile.fans.count
        if Self.validFans(state.fans, count: fanCount) == nil {
            if let stock = Self.validFans(checks.stockFanRanges(count: fanCount), count: fanCount) {
                state.fans = stock
                persistState()
            }
            // A fallback to the profile ranges is not saved: the next start reads the SMC again.
            controller = Controller(config: config, fans: Self.validFans(state.fans, count: fanCount) ?? profile.fans)
        }
        let (starts, tripped) = CrashLoopGuard.recordStart(at: wall, previous: state.starts)
        state.starts = starts
        persistState()
        if tripped { return enterSafe(.crashLoop, now: now) }
        execute(controller.startup(.ok), now: now)
        logModeChange()
    }

    /// Re-runs the startup checks from safe mode without counting a start; does nothing in any other mode.
    func retry(now: Double) {
        guard case .safe = controller.mode else { return }
        guard checks.modelIdentifier() == profile.model else { return enterSafe(.unsupportedModel, now: now) }
        guard hardwareKeysPresent() else { return enterSafe(.missingKeys, now: now) }
        execute(controller.startup(.ok), now: now)
        logModeChange()
    }

    public func willSleep(now: Double) {
        execute(controller.willSleep(), now: now)
        logModeChange()
    }

    public func didWake(now: Double) {
        controller.didWake(at: now)
        logModeChange()
    }

    /// SIGTERM / SIGINT: hand the fans back whatever the mode. An unsupported model never touches the SMC.
    public func shutdown(now: Double) {
        if controller.mode == .safe(.unsupportedModel) {
            log("shutting down (unsupported model, SMC untouched)")
            return
        }
        releaseFans(now: now)
        if releaseOwed {
            log("shutting down, but the fans could not be handed back; the watchdog will retry")
        } else {
            log("shutting down, fans handed back to macOS")
        }
    }

    // MARK: Tick

    public func tick(now: Double, wall: Double) {
        guard started else { return }
        let readings = sensors.read()
        let input = profile.tickInput(time: now) { readings[$0] }
        let output = controller.tick(input)
        execute(output.actions, now: now)
        if releaseOwed, controller.mode != .active {
            releaseFans(now: now)
        }
        // Touched on every tick in any mode, except one case: while the daemon has not managed to
        // hand the fans back (see releaseOwed), the heartbeat is withheld so the watchdog tries too.
        if !releaseOwed, !Heartbeat.touch(paths.heartbeat) {
            logLimited("heartbeat \(paths.heartbeat.path) could not be updated", now: now)
        }
        if controller.mode == .active, output.actions.isEmpty, let target = output.targetRPM,
           lastWriteAt.map({ now - $0 >= Self.verifyDelaySeconds }) ?? true,
           !actuator.verify(targetRPM: target) {
            reassert(target, now: now)
        }
        lastOutput = output
        lastFanRPM = input.fanRPM
        recordSample(output, fanRPM: input.fanRPM, wall: wall)
        logModeChange()
    }

    // MARK: Socket commands

    func snapshot(now: Double, wall: Double) -> Snapshot {
        let targets = lastOutput?.targetRPM
        let fanStates = controller.fans.enumerated().map { index, range in
            FanState(actualRPM: index < lastFanRPM.count ? lastFanRPM[index] : nil,
                     targetRPM: targets.flatMap { index < $0.count ? $0[index] : nil },
                     minRPM: range.minRPM, maxRPM: range.maxRPM)
        }
        return Snapshot(t: wall, mode: controller.mode,
                        raw: lastOutput?.raw ?? .empty, filtered: lastOutput?.filtered ?? .empty,
                        demand: lastOutput?.demand ?? .empty, outputPercent: lastOutput?.outputPercent,
                        fans: fanStates,
                        gpuPolicy: gpuPolicy.state(enabled: config.gpuPolicy.enabled, now: now),
                        configError: configError, smcError: recentSMCError(now: now))
    }

    func history(seconds: Int) -> [Sample] {
        history.suffix(seconds)
    }

    /// Takes the curves and smoothing from `requested`; `enabled` and the GPU policy have their own commands.
    func setConfig(_ requested: Config) throws -> Config {
        var next = config
        next.curves = requested.curves
        next.smoothing = requested.smoothing
        try next.validate()
        try configStore.save(next)
        try controller.setConfig(next)
        config = next
        configError = nil
        return next
    }

    func setEnabled(_ enabled: Bool, now: Double) throws {
        if case .safe = controller.mode {
            throw ValidationError(message: "safe mode: retry first")
        }
        var next = config
        next.enabled = enabled
        if enabled {
            try configStore.save(next)
            config = next
            execute(controller.setEnabled(true), now: now)
        } else {
            // Hand the fans back first: a failed save must not keep them from macOS.
            config = next
            execute(controller.setEnabled(false), now: now)
            try configStore.save(next)
        }
        logModeChange()
    }

    func setGPUPolicy(_ enabled: Bool, now: Double) throws -> GPUPolicyState {
        if enabled {
            if state.gpuSwitchOriginal == nil {
                // Read and save the originals before the first pmset write; a failed save cancels
                // the switch, or a later disable would have nothing to restore.
                var next = state
                next.gpuSwitchOriginal = try gpuPolicy.readCurrent()
                try stateStore.save(next)
                state = next
            }
            try gpuPolicy.enable(now: now)
        } else {
            try gpuPolicy.disable(savedOriginal: state.gpuSwitchOriginal, now: now)
            if state.gpuSwitchOriginal != nil {
                // The next enable reads fresh originals, so a choice made after auto-graphics was
                // switched off is not later reverted by `fancurved --restore`.
                var next = state
                next.gpuSwitchOriginal = nil
                try stateStore.save(next)
                state = next
            }
        }
        var next = config
        next.gpuPolicy.enabled = enabled
        try configStore.save(next)
        config = next
        return gpuPolicy.state(enabled: enabled, now: now)
    }

    // MARK: Private

    /// Stored or stock ranges are trusted only when they fit the profile: one per fan, each usable.
    private static func validFans(_ fans: [FanRange]?, count: Int) -> [FanRange]? {
        guard let fans, fans.count == count, fans.allSatisfy(\.isUsable) else { return nil }
        return fans
    }

    private func hardwareKeysPresent() -> Bool {
        guard checks.missingKeys(profile.requiredFanKeys).isEmpty else { return false }
        return checks.missingKeys(profile.cpuTemps).count < profile.cpuTemps.count
    }

    private func enterSafe(_ reason: SafeReason, now: Double) {
        execute(controller.startup(.failed(reason)), now: now)
        logModeChange()
    }

    private func execute(_ actions: [ActuatorAction], now: Double) {
        for action in actions {
            switch action {
            case .apply(let rpm):
                force(rpm, now: now)
            case .release:
                releaseFans(now: now)
            }
            // A write failure may have just moved the controller to safe mode: write nothing more.
            if case .safe = controller.mode { break }
        }
    }

    /// A failed write makes the controller write its target again next tick;
    /// `maxConsecutiveWriteFailures` in a row hand the fans back: safe(smcWriteFailed).
    private func write(now: Double, _ body: () throws -> Void) {
        do {
            try body()
            lastWriteAt = now
            consecutiveWriteFailures = 0
            releaseOwed = false  // we hold the fans again; nothing is owed to macOS
        } catch {
            noteSMCError(error, now: now)
            controller.invalidateLastWrite()
            consecutiveWriteFailures += 1
            if consecutiveWriteFailures >= Self.maxConsecutiveWriteFailures {
                consecutiveWriteFailures = 0
                log("\(Self.maxConsecutiveWriteFailures) SMC writes failed in a row, handing the fans back to macOS")
                enterSafe(.smcWriteFailed, now: now)
            }
        }
    }

    /// Forced mode goes with every target: the first target of a takeover takes the fans, and the SMC
    /// can drop the mode (sleep, a watchdog release after a stall) while a ramp leaves no quiet tick
    /// for the readback to catch it.
    private func force(_ rpm: [Int], now: Double) {
        write(now: now) {
            try actuator.take()
            try actuator.apply(rpm: rpm)
        }
    }

    private func reassert(_ target: [Int], now: Double) {
        logLimited("SMC readback differs from the target, re-asserting forced mode", now: now)
        force(target, now: now)
    }

    /// Hands the fans back to macOS. Failing twice leaves the release owed (see `releaseOwed`).
    private func releaseFans(now: Double) {
        // A hand-back ends whatever write-failure streak preceded it: a fresh forced-mode attempt
        // (after sleep, a retry) must not inherit failures counted before the fans went back to macOS.
        consecutiveWriteFailures = 0
        lastWriteAt = now
        do {
            try actuator.release()
            releaseOwed = false
        } catch {
            noteSMCError(error, now: now)
            do {
                try actuator.release()
                releaseOwed = false
            } catch {
                noteSMCError(error, now: now)
                releaseOwed = true
            }
        }
    }

    private func noteSMCError(_ error: Error, now: Double) {
        let message = "\(error)"
        lastSMCError = (message, now)
        logLimited("SMC write failed: \(message)", now: now)
    }

    private func logLimited(_ message: String, now: Double) {
        if logLimiter.shouldLog(message, now: now) { log(message) }
    }

    private func recentSMCError(now: Double) -> String? {
        guard let lastSMCError, now - lastSMCError.at < Self.smcErrorHoldSeconds else { return nil }
        return lastSMCError.message
    }

    private func recordSample(_ output: TickOutput, fanRPM: [Double?], wall: Double) {
        let second = Int(wall.rounded(.down))
        guard second != lastSampleSecond else { return }
        lastSampleSecond = second
        history.append(Sample(t: wall, cpu: output.raw.cpu, gpu: output.raw.gpu, chassis: output.raw.chassis,
                              power: output.raw.power, demandPercent: output.demand.percent,
                              leading: output.demand.leading, fanRPM: fanRPM, mode: output.mode))
    }

    private func persistState() {
        do {
            try stateStore.save(state)
        } catch {
            log("state.json not saved: \(error)")
        }
    }

    private func logModeChange() {
        guard controller.mode != loggedMode else { return }
        loggedMode = controller.mode
        log("mode: \(controller.mode.label)")
    }
}
