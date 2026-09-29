import FanCurveCore
import FanCurveHardware

/// One reading of every profile column per call; absent values are simply missing.
public protocol SensorSource: AnyObject {
    func read() -> [String: Double]
}

/// Takes, drives and hands back the fans; `ForcedActuator` is the real one.
public protocol FanActuating: AnyObject {
    func take() throws
    func apply(rpm: [Int]) throws
    func release() throws
    func verify(targetRPM: [Int]) -> Bool
}

/// The startup checks: the Mac's model, the SMC keys, the stock fan ranges.
public protocol HardwareChecks: AnyObject {
    func modelIdentifier() -> String?
    /// The names from `names` whose SMC key does not exist.
    func missingKeys(_ names: [String]) -> [String]
    /// Stock (F?Mn, F?Mx) per fan as the SMC reports them now; nil if any read fails.
    func stockFanRanges(count: Int) -> [FanRange]?
}

extension LiveSensors: SensorSource {}
extension ForcedActuator: FanActuating {}

/// Startup checks against the real SMC; with no SMC (AppleSMC did not open) every key is missing.
public final class SMCHardwareChecks: HardwareChecks {
    private let smc: SMCAccess?

    public init(smc: SMCAccess?) {
        self.smc = smc
    }

    public func modelIdentifier() -> String? {
        SystemInfo.hardwareModel()
    }

    public func missingKeys(_ names: [String]) -> [String] {
        guard let smc else { return names }
        return names.filter { name in SMCKey(name).flatMap { try? smc.keyInfo($0) } == nil }
    }

    public func stockFanRanges(count: Int) -> [FanRange]? {
        guard let smc, let limits = SystemInfo.stockFanLimits(smc: smc, count: count) else { return nil }
        return limits.map { FanRange(minRPM: $0.min, maxRPM: $0.max) }
    }
}

/// Used when AppleSMC could not be opened: no readings.
public final class NoSensors: SensorSource {
    public init() {}
    public func read() -> [String: Double] { [:] }
}

/// Used when AppleSMC could not be opened: every write fails (the daemon is in safe mode anyway).
public final class UnavailableActuator: FanActuating {
    public init() {}
    public func take() throws { throw SMCError.serviceNotFound }
    public func apply(rpm: [Int]) throws { throw SMCError.serviceNotFound }
    public func release() throws { throw SMCError.serviceNotFound }
    public func verify(targetRPM: [Int]) -> Bool { false }
}

/// `--dry-run`: logs what it would write and reports every write as having stuck.
public final class LoggingActuator: FanActuating {
    private let log: (String) -> Void

    public init(log: @escaping (String) -> Void) {
        self.log = log
    }

    public func take() throws { log("dry-run: take") }
    public func apply(rpm: [Int]) throws { log("dry-run: apply \(rpm)") }
    public func release() throws { log("dry-run: release") }
    public func verify(targetRPM: [Int]) -> Bool { true }
}

/// `--dry-run`: reads the real pmset values, logs writes instead of making them.
public final class DryRunGPUSwitch: GPUSwitchControl {
    private let log: (String) -> Void
    private var written: GPUSwitchValues?

    public init(log: @escaping (String) -> Void) {
        self.log = log
    }

    public func read() throws -> GPUSwitchValues {
        if let written { return written }
        return try PMSetSwitch().read()
    }

    public func set(_ values: GPUSwitchValues) throws {
        log("dry-run: pmset gpuswitch ac \(values.ac) battery \(values.battery)")
        written = values
    }
}
