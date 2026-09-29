import FanCurveCore
import FanCurveHardware

/// Reads and writes the per-power-source `gpuswitch` setting.
public protocol GPUSwitchControl: AnyObject {
    func read() throws -> GPUSwitchValues
    func set(_ values: GPUSwitchValues) throws
}

enum GPUSwitchError: Error, CustomStringConvertible {
    case unreadable

    var description: String {
        "pmset -g custom: no gpuswitch for the charger and the battery"
    }
}

/// The real control: /usr/bin/pmset. Writes need root.
public final class PMSetSwitch: GPUSwitchControl {
    public init() {}

    public func read() throws -> GPUSwitchValues {
        let values = try PMSet.readGPUSwitch()
        guard let ac = values.ac, let battery = values.battery else { throw GPUSwitchError.unreadable }
        return GPUSwitchValues(ac: ac, battery: battery)
    }

    public func set(_ values: GPUSwitchValues) throws {
        try PMSet.setGPUSwitch(ac: values.ac, battery: values.battery)
    }
}

/// Auto-graphics: the Radeon on the charger, automatic switching on battery. macOS itself switches
/// graphics when the cable is plugged in; this only sets the per-source values. It stores nothing;
/// the engine saves the originals before calling `enable`.
public final class GPUPolicy {
    /// pmset is a subprocess; the popup asks for the state every second.
    static let refreshSeconds = 30.0

    private let control: GPUSwitchControl
    private var cached: GPUSwitchValues?
    private var cachedAt: Double?

    public init(control: GPUSwitchControl) {
        self.control = control
    }

    /// The values as set now, re-read at most every `refreshSeconds`; nil if unreadable.
    func current(now: Double) -> GPUSwitchValues? {
        if let cachedAt, now >= cachedAt, now - cachedAt < Self.refreshSeconds {
            return cached
        }
        cached = try? control.read()
        cachedAt = now
        return cached
    }

    /// The values as set right now, read fresh — the caller saves them before the first change.
    func readCurrent() throws -> GPUSwitchValues {
        try control.read()
    }

    /// Sets AC 1 / battery 2. The caller has saved the originals first.
    func enable(now: Double) throws {
        try write(.chargerDiscrete, now: now)
    }

    /// Writes the originals back; nothing to do if auto-graphics was never switched on.
    func disable(savedOriginal: GPUSwitchValues?, now: Double) throws {
        if let savedOriginal {
            try write(savedOriginal, now: now)
        }
    }

    /// The values written are the values `current` reports, without another pmset call. A failed
    /// write may have set one power source and not the other, so the next `current` reads again.
    private func write(_ values: GPUSwitchValues, now: Double) throws {
        do {
            try control.set(values)
            cached = values
            cachedAt = now
        } catch {
            cachedAt = nil
            throw error
        }
    }

    func state(enabled: Bool, now: Double) -> GPUPolicyState {
        let values = current(now: now)
        return GPUPolicyState(enabled: enabled, acSwitch: values?.ac, batterySwitch: values?.battery)
    }
}
