public enum ReleaseReason: String, Codable, Sendable {
    case sensorLoss
    case sleep
}

public enum SafeReason: String, Codable, Sendable {
    case crashLoop
    case unsupportedModel
    case missingKeys
    case smcWriteFailed
}

public enum Mode: Equatable, Sendable {
    case starting
    case active
    case released(ReleaseReason)
    case disabled
    case safe(SafeReason)

    /// Short form for logs and CLI output, e.g. "released:sleep".
    public var label: String {
        switch self {
        case .starting: return "starting"
        case .active: return "active"
        case .disabled: return "disabled"
        case .released(let reason): return "released:\(reason.rawValue)"
        case .safe(let reason): return "safe:\(reason.rawValue)"
        }
    }
}

public enum StartupCheck: Equatable, Sendable {
    case ok
    case failed(SafeReason)
}

/// What the daemon does to the fans. Taking control has no action of its own: the daemon forces the
/// fans' mode with every target it writes, so the first `.apply` of a takeover takes them.
public enum ActuatorAction: Equatable, Sendable {
    case apply([Int])
    case release
}

public struct TickInput: Equatable, Sendable {
    public var time: Double
    public var channels: PerChannel<Double?>
    public var gpuActive: Bool
    /// Tachometer readings, one per fan; nil where a fan does not read. Non-finite readings count as
    /// missing (`HardwareProfile.tickInput`, `FanRange.fasterPercent`).
    public var fanRPM: [Double?]

    public init(time: Double, channels: PerChannel<Double?>, gpuActive: Bool, fanRPM: [Double?]) {
        self.time = time
        self.channels = channels
        self.gpuActive = gpuActive
        self.fanRPM = fanRPM
    }
}

public struct TickOutput: Equatable, Sendable {
    public var mode: Mode
    public var raw: PerChannel<Double?>
    public var filtered: PerChannel<Double?>
    public var demand: DemandResult
    public var outputPercent: Double?
    /// Non-nil on every `.active` tick: the authoritative per-tick target the daemon must verify
    /// and re-assert. `.apply` signals that a write is due (a takeover, a changed target, or a
    /// re-send after `invalidateLastWrite()`), not only that the target changed.
    public var targetRPM: [Int]?
    public var actions: [ActuatorAction]
}

public enum ControllerLimits {
    public static let temperatureTau = 2.0
    public static let powerTau = 10.0
    public static let lossTicks = 3
    public static let criticalTemperature = 95.0
    public static let recoverySeconds = 10.0
    public static let startupWaitSeconds = 3.0
    public static let wakePauseSeconds = 5.0
}

/// Pure control state machine. The daemon feeds it events and ticks and executes the returned actions in order.
public struct Controller: Sendable {
    public private(set) var mode: Mode = .starting
    private(set) var config: Config
    public let fans: [FanRange]

    private var filters = PerChannel(
        cpu: ChannelFilter(tau: ControllerLimits.temperatureTau, lossTicks: ControllerLimits.lossTicks),
        gpu: ChannelFilter(tau: ControllerLimits.temperatureTau, lossTicks: ControllerLimits.lossTicks),
        chassis: ChannelFilter(tau: ControllerLimits.temperatureTau, lossTicks: ControllerLimits.lossTicks),
        power: ChannelFilter(tau: ControllerLimits.powerTau, lossTicks: ControllerLimits.lossTicks)
    )
    private var smoother = OutputSmoother()
    private var hasControl = false
    private var lastWritten: Double?
    private var startupDeadline: Double?
    private var criticalValidSince: Double?
    private var wakeResumeAt: Double?

    public init(config: Config, fans: [FanRange]) {
        self.config = config
        self.fans = fans
    }

    // MARK: Events

    /// After the daemon's startup checks and after a retry; `.failed` also moves a running controller
    /// to safe mode (the daemon does that after repeated SMC write failures).
    public mutating func startup(_ check: StartupCheck) -> [ActuatorAction] {
        let actions = relinquish()
        switch check {
        case .ok:
            mode = config.enabled ? .starting : .disabled
        case .failed(let reason):
            mode = .safe(reason)
        }
        startupDeadline = nil
        criticalValidSince = nil
        wakeResumeAt = nil
        return actions
    }

    /// Replaces curves and smoothing only.
    public mutating func setConfig(_ new: Config) throws {
        try new.validate()
        config.curves = new.curves
        config.smoothing = new.smoothing
    }

    public mutating func setEnabled(_ enabled: Bool) -> [ActuatorAction] {
        if case .safe = mode { return [] }
        config.enabled = enabled
        if enabled {
            if mode == .disabled {
                mode = .starting
                startupDeadline = nil
            }
            return []
        }
        mode = .disabled
        return relinquish()
    }

    public mutating func willSleep() -> [ActuatorAction] {
        switch mode {
        case .starting, .active, .released(.sensorLoss):
            mode = .released(.sleep)
            wakeResumeAt = nil
            return relinquish()
        case .released(.sleep), .disabled, .safe:
            return []
        }
    }

    public mutating func didWake(at time: Double) {
        for id in ChannelID.allCases {
            filters[id].reset()
        }
        criticalValidSince = nil
        if mode == .active {
            // The SMC clears the forced fan mode across sleep (traces/sleep-test.txt), so a wake
            // delivered while we never got a willSleep() leaves the hardware back under macOS even
            // though we still think we're `.active`. Route through the same pause-then-retake path.
            mode = .released(.sleep)
        }
        if mode == .released(.sleep) {
            wakeResumeAt = time + ControllerLimits.wakePauseSeconds
        }
    }

    /// Call when an `.apply` could not be written, so the next tick re-emits it.
    public mutating func invalidateLastWrite() { lastWritten = nil }

    // MARK: Tick

    public mutating func tick(_ input: TickInput) -> TickOutput {
        let time = input.time
        var raw = input.channels
        let radeonAsleep = !input.gpuActive
        if radeonAsleep {
            raw.gpu = nil
            filters.gpu.clearValue()
        }
        for id in ChannelID.allCases {
            if !(id == .gpu && radeonAsleep) {
                filters[id].update(raw[id], at: time)
            }
        }
        let filtered = filters.map { $0.value }
        let demand = Demand.evaluate(curves: config.curves, values: filtered)

        let criticalReady = filtered.cpu != nil && (radeonAsleep || filtered.gpu != nil)
        let criticalLost = filters.cpu.isLost || (!radeonAsleep && filters.gpu.isLost)
        criticalValidSince = criticalReady ? (criticalValidSince ?? time) : nil
        let overheat = (raw.cpu ?? 0) >= ControllerLimits.criticalTemperature
            || (raw.gpu ?? 0) >= ControllerLimits.criticalTemperature

        var actions: [ActuatorAction] = []
        switch mode {
        case .starting:
            let deadline = startupDeadline ?? time + ControllerLimits.startupWaitSeconds
            startupDeadline = deadline
            if criticalReady {
                takeControl(input)
            } else if time >= deadline {
                mode = .released(.sensorLoss)
                actions += relinquish()
            }
        case .active:
            if criticalLost {
                mode = .released(.sensorLoss)
                actions += relinquish()
            }
        case .released(.sensorLoss):
            if let since = criticalValidSince, time - since >= ControllerLimits.recoverySeconds {
                takeControl(input)
            }
        case .released(.sleep):
            if let resume = wakeResumeAt, time >= resume {
                wakeResumeAt = nil
                if criticalReady {
                    takeControl(input)
                } else {
                    mode = .released(.sensorLoss)
                    actions += relinquish()
                }
            }
        case .disabled, .safe:
            break
        }

        var outputPercent: Double?
        var targetRPM: [Int]?
        if mode == .active {
            let wanted = overheat ? 100 : demand.percent
            let output = smoother.step(demand: wanted, at: time, smoothing: config.smoothing, bypass: overheat)
            if WriteGate.shouldWrite(output, lastWritten: lastWritten, deadband: config.smoothing.deadbandPercent) {
                lastWritten = output
                actions.append(.apply(fans.map { $0.rpm(forPercent: output) }))
            }
            outputPercent = output
            targetRPM = lastWritten.map { written in fans.map { $0.rpm(forPercent: written) } }
        }
        return TickOutput(mode: mode, raw: raw, filtered: filtered, demand: demand,
                          outputPercent: outputPercent, targetRPM: targetRPM, actions: actions)
    }

    // MARK: Private

    /// Continues from the fans' current speed; clearing `lastWritten` makes this tick's `.apply`.
    private mutating func takeControl(_ input: TickInput) {
        mode = .active
        // No tachometer reading: a cooling tool fails loud, not silent.
        let current = FanRange.fasterPercent(rpm: input.fanRPM, ranges: fans) ?? 100
        smoother.reset(output: current, at: input.time)
        lastWritten = nil
        hasControl = true
    }

    /// Hands the fans back to macOS if we hold them.
    private mutating func relinquish() -> [ActuatorAction] {
        lastWritten = nil
        guard hasControl else { return [] }
        hasControl = false
        return [.release]
    }
}
