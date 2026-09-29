import FanCurveCore
import Foundation

/// Plain-text output of `fancurvectl`.
public enum StatusText {
    public static func render(_ snapshot: Snapshot) -> String {
        var lines = ["mode: \(snapshot.mode.label)"]
        let raw = snapshot.raw
        lines.append("cpu \(celsius(raw.cpu))  gpu \(celsius(raw.gpu))  chassis \(celsius(raw.chassis))  power \(watts(raw.power))")
        let demand = snapshot.demand
        let leader: String
        switch demand.leading {
        case .hotspot?: leader = "hotspot on \(demand.hotDie?.rawValue ?? "?")"
        case let kind?: leader = kind.rawValue
        case nil: leader = "none"
        }
        lines.append("demand \(percent(demand.percent)) (\(leader))  hotspot \(percent(demand.hotspot))  "
            + "power \(percent(demand.power))  chassis \(percent(demand.chassis))  output \(percent(snapshot.outputPercent))")
        for (index, fan) in snapshot.fans.enumerated() {
            let actual = fan.actualRPM.map { String(format: "%.0f", $0) } ?? "—"
            let target = fan.targetRPM.map(String.init) ?? "—"
            lines.append("fan\(index) \(actual) rpm → \(target) (" + String(format: "%.0f-%.0f", fan.minRPM, fan.maxRPM) + ")")
        }
        lines.append(gpuPolicy(snapshot.gpuPolicy))
        if let error = snapshot.configError { lines.append("config error: \(error)") }
        if let error = snapshot.smcError { lines.append("smc error: \(error)") }
        return lines.joined(separator: "\n")
    }

    public static func gpuPolicy(_ state: GPUPolicyState) -> String {
        let ac = state.acSwitch.map(String.init) ?? "?"
        let battery = state.batterySwitch.map(String.init) ?? "?"
        return "auto-graphics \(state.enabled ? "on" : "off") (gpuswitch ac \(ac), battery \(battery))"
    }

    /// One fan column per fan of the sample with the most.
    public static func csv(_ samples: [Sample]) -> String {
        let fanCount = samples.map(\.fanRPM.count).max() ?? 0
        var text = "t,mode,cpu,gpu,chassis,power,demand,leading" + (0..<fanCount).map { ",fan\($0)" }.joined() + "\n"
        for sample in samples {
            let fans = (0..<fanCount).map { $0 < sample.fanRPM.count ? number(sample.fanRPM[$0]) : "" }
            let fields = [String(format: "%.0f", sample.t), sample.mode.label, number(sample.cpu), number(sample.gpu),
                          number(sample.chassis), number(sample.power), number(sample.demandPercent),
                          sample.leading?.rawValue ?? ""] + fans
            text += fields.joined(separator: ",") + "\n"
        }
        return text
    }

    static func celsius(_ value: Double?) -> String { value.map { String(format: "%.1f°C", $0) } ?? "—" }
    static func watts(_ value: Double?) -> String { value.map { String(format: "%.1f W", $0) } ?? "—" }
    static func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
    static func number(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "" }
}
