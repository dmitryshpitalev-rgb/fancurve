public struct Threshold: Codable, Equatable, Sendable {
    public var column: String
    public var above: Double

    public init(column: String, above: Double) {
        self.column = column
        self.above = above
    }
}

/// Where each channel comes from on this Mac; docs/hardware-profile.json holds the same for fancurved --simulate.
/// Names are SMC keys (e.g. "TCXC") or ioreg columns ("ioreg.gpu.temp", "ioreg.gpu.power").
public struct HardwareProfile: Codable, Equatable, Sendable {
    public var model: String
    public var cpuTemps: [String]
    public var gpuTemps: [String]
    public var gpuIoregTemp: String?
    public var chassisTemps: [String]
    public var cpuPower: String?
    public var gpuPower: String?
    public var gpuActiveRule: Threshold?
    public var fanActual: [String]
    /// Per-fan SMC keys the actuator writes, in fans order: mode (e.g. "F0Md") and target (e.g. "F0Tg").
    public var fanMode: [String]
    public var fanTarget: [String]
    public var fans: [FanRange]

    public init(model: String, cpuTemps: [String], gpuTemps: [String], gpuIoregTemp: String?,
                chassisTemps: [String], cpuPower: String?, gpuPower: String?, gpuActiveRule: Threshold?,
                fanActual: [String], fanMode: [String], fanTarget: [String], fans: [FanRange]) {
        self.model = model
        self.cpuTemps = cpuTemps
        self.gpuTemps = gpuTemps
        self.gpuIoregTemp = gpuIoregTemp
        self.chassisTemps = chassisTemps
        self.cpuPower = cpuPower
        self.gpuPower = gpuPower
        self.gpuActiveRule = gpuActiveRule
        self.fanActual = fanActual
        self.fanMode = fanMode
        self.fanTarget = fanTarget
        self.fans = fans
    }

    /// Builds one controller input; `value` returns the reading for a key or column name.
    public func tickInput(time: Double, value: (String) -> Double?) -> TickInput {
        let gpuTemperature = ChannelMath.gpuTemperature(smc: gpuTemps.map(value), ioreg: gpuIoregTemp.flatMap(value))
        let gpuActive: Bool
        if let rule = gpuActiveRule {
            // An unreadable rail (column present in the profile but missing from this reading) must
            // not look like a sleeping Radeon: that would silently disarm both the GPU channel and
            // the GPU overheat override. Only a rule that actually reads a value below threshold
            // means "off"; no reading at all defaults to "on".
            gpuActive = value(rule.column).flatMap { $0.isFinite ? $0 : nil }.map { $0 > rule.above } ?? true
        } else {
            gpuActive = gpuTemperature != nil
        }
        let channels = PerChannel<Double?>(
            cpu: ChannelMath.temperature(cpuTemps.map(value)),
            gpu: gpuTemperature,
            chassis: ChannelMath.temperature(chassisTemps.map(value)),
            power: ChannelMath.power(cpuPackage: cpuPower.flatMap(value), gpu: gpuPower.flatMap(value), gpuActive: gpuActive)
        )
        // A non-finite tachometer reading (NaN, or ± infinity) reads as missing, not as a number:
        // `Int(NaN)` traps in `FanRange.rpm(forPercent:)`, and a non-finite value fails to encode
        // in every status/history reply while it is active.
        return TickInput(time: time, channels: channels, gpuActive: gpuActive,
                          fanRPM: fanActual.map { value($0).flatMap { $0.isFinite ? $0 : nil } })
    }
}

extension HardwareProfile {
    /// This Mac as measured. Must equal docs/hardware-profile.json (a test checks it).
    public static let macBookPro16_1 = HardwareProfile(
        model: "MacBookPro16,1",
        cpuTemps: ["TC0E", "TC0F", "TC0P", "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C", "TC8C",
                   "TCGC", "TCMX", "TCSA", "TCXC"],
        gpuTemps: ["TG0P", "TGDD", "TGDF"],
        gpuIoregTemp: "ioreg.gpu.temp",
        chassisTemps: ["Ts0S", "Ts1S", "Ts2S"],
        cpuPower: "PC0R",
        gpuPower: "ioreg.gpu.power",
        gpuActiveRule: Threshold(column: "PG0R", above: 1.0),
        fanActual: ["F0Ac", "F1Ac"],
        fanMode: ["F0Md", "F1Md"],
        fanTarget: ["F0Tg", "F1Tg"],
        fans: [FanRange(minRPM: 1836, maxRPM: 5616), FanRange(minRPM: 1700, maxRPM: 5200)]
    )

    /// Every reading `tickInput` asks for, once each, in the profile's field order.
    public var columnNames: [String] {
        let all = cpuTemps + gpuTemps + [gpuIoregTemp].compactMap { $0 } + chassisTemps
            + [cpuPower, gpuPower, gpuActiveRule?.column].compactMap { $0 } + fanActual
        var names: [String] = []
        for name in all where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    /// SMC keys the daemon cannot run without: every fan's mode, target and tachometer.
    public var requiredFanKeys: [String] {
        fanMode + fanTarget + fanActual
    }
}
