/// Turns raw sensor readings into channel values.
public enum ChannelMath {
    /// A temperature reading outside this range is a sensor fault and is dropped, so no channel
    /// value lies outside it.
    public static let temperatureRange: ClosedRange<Double> = 0...115
    static let powerRange: ClosedRange<Double> = 0...500

    /// Highest reading inside the valid temperature range; nil if there is none.
    static func temperature(_ readings: [Double?]) -> Double? {
        readings.compactMap { $0 }.filter { $0.isFinite && temperatureRange.contains($0) }.max()
    }

    /// SMC GPU keys first, the ioreg temperature as a fallback.
    static func gpuTemperature(smc: [Double?], ioreg: Double?) -> Double? {
        temperature(smc) ?? temperature([ioreg])
    }

    /// CPU package plus Radeon power; the Radeon counts as 0 W when it is off or unreadable.
    /// nil when the CPU package reading is missing or invalid.
    static func power(cpuPackage: Double?, gpu: Double?, gpuActive: Bool) -> Double? {
        guard let cpu = cpuPackage, cpu.isFinite, powerRange.contains(cpu) else { return nil }
        guard gpuActive, let gpu, gpu.isFinite, powerRange.contains(gpu) else { return cpu }
        return cpu + gpu
    }
}

public struct DemandResult: Codable, Equatable, Sendable {
    /// Each curve's demand in percent; nil when its input is missing or the curve is switched off.
    public var hotspot: Double?
    public var power: Double?
    public var chassis: Double?
    /// The die that fed the hotspot curve; nil when neither die reads.
    public var hotDie: ChannelID?
    public var leading: CurveKind?
    public var percent: Double

    public init(hotspot: Double?, power: Double?, chassis: Double?, hotDie: ChannelID?, leading: CurveKind?, percent: Double) {
        self.hotspot = hotspot
        self.power = power
        self.chassis = chassis
        self.hotDie = hotDie
        self.leading = leading
        self.percent = percent
    }

    /// No curve has an input, so none demands anything.
    public static let empty = DemandResult(hotspot: nil, power: nil, chassis: nil, hotDie: nil, leading: nil, percent: 0)

    public subscript(kind: CurveKind) -> Double? {
        switch kind {
        case .hotspot: return hotspot
        case .power: return power
        case .chassis: return chassis
        }
    }
}

public enum Demand {
    /// The hotter die (a tie goes to the CPU) feeds the hotspot curve; each switched-on aux curve reads
    /// its own channel; the demand is the maximum, ties going to the earlier `CurveKind` case.
    public static func evaluate(curves: CurveSet, values: PerChannel<Double?>) -> DemandResult {
        var result = DemandResult.empty
        if let cpu = values.cpu, cpu >= (values.gpu ?? -.infinity) {
            result.hotspot = curves.hotspot.evaluate(cpu)
            result.hotDie = .cpu
        } else if let gpu = values.gpu {
            result.hotspot = curves.hotspot.evaluate(gpu)
            result.hotDie = .gpu
        }
        if curves.power.enabled, let watts = values.power {
            result.power = curves.power.curve.evaluate(watts)
        }
        if curves.chassis.enabled, let chassis = values.chassis {
            result.chassis = curves.chassis.curve.evaluate(chassis)
        }
        for kind in CurveKind.allCases {
            guard let demand = result[kind] else { continue }
            if result.leading == nil || demand > result.percent {
                result.leading = kind
                result.percent = demand
            }
        }
        return result
    }
}
