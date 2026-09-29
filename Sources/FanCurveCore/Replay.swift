import Foundation

/// A CSV trace written by `smc-probe record`: header row, first column "t", empty cell = no value;
/// any other cell must be a number.
public struct Trace: Equatable, Sendable {
    public let columns: [String]
    public let rows: [[Double?]]

    public static func parse(csv: String) throws -> Trace {
        let lines = csv.split(whereSeparator: \.isNewline)
        guard let header = lines.first else {
            throw ValidationError(message: "the trace is empty")
        }
        let columns = header.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard columns.first == "t" else {
            throw ValidationError(message: "the first trace column must be t")
        }
        var rows: [[Double?]] = []
        for (offset, line) in lines.dropFirst().enumerated() {
            let lineNumber = offset + 2
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == columns.count else {
                throw ValidationError(message: "line \(lineNumber): \(fields.count) fields, expected \(columns.count)")
            }
            var values: [Double?] = []
            for (column, field) in zip(columns, fields) {
                if field.isEmpty {
                    values.append(nil)
                } else if let value = Double(field) {
                    values.append(value)
                } else {
                    throw ValidationError(message: "line \(lineNumber), column \(column): \"\(field)\" is not a number")
                }
            }
            guard let t = values[0] else {
                throw ValidationError(message: "line \(lineNumber): no time t")
            }
            guard t.isFinite else {
                throw ValidationError(message: "line \(lineNumber): time t is not a number")
            }
            rows.append(values)
        }
        return Trace(columns: columns, rows: rows)
    }
}

public struct ReplayRow: Equatable, Sendable {
    public var t: Double
    public var mode: Mode
    public var filtered: PerChannel<Double?>
    public var leading: CurveKind?
    public var hotDie: ChannelID?
    public var demandPercent: Double
    public var outputPercent: Double?
    public var targetRPM: [Int]?
}

public enum Replay {
    /// Feeds every trace row through a fresh controller, as if the daemon had started at the first row.
    public static func run(trace: Trace, profile: HardwareProfile, config: Config) -> [ReplayRow] {
        let index = Dictionary(trace.columns.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var controller = Controller(config: config, fans: profile.fans)
        _ = controller.startup(.ok)
        return trace.rows.map { row in
            let input = profile.tickInput(time: row[0] ?? 0) { name in
                index[name].flatMap { row[$0] }
            }
            let output = controller.tick(input)
            return ReplayRow(t: input.time, mode: output.mode, filtered: output.filtered, leading: output.demand.leading,
                             hotDie: output.demand.hotDie, demandPercent: output.demand.percent, outputPercent: output.outputPercent,
                             targetRPM: output.targetRPM)
        }
    }

    public static func csv(_ rows: [ReplayRow]) -> String {
        func number(_ value: Double?) -> String {
            value.map { String(format: "%.2f", $0) } ?? ""
        }
        var text = "t,mode,cpu,gpu,chassis,power,leading,die,demand,output,rpm\n"
        for row in rows {
            let rpm = row.targetRPM.map { $0.map(String.init).joined(separator: "/") } ?? ""
            let fields = [
                number(row.t), row.mode.label,
                number(row.filtered.cpu), number(row.filtered.gpu), number(row.filtered.chassis), number(row.filtered.power),
                row.leading?.rawValue ?? "", row.hotDie?.rawValue ?? "",
                number(row.demandPercent), number(row.outputPercent), rpm,
            ]
            text += fields.joined(separator: ",") + "\n"
        }
        return text
    }
}
