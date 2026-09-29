import Foundation

/// The smoothing settings in `Smoothing` order: up, hold, down, deadband. The raw value is the
/// config key, which the daemon's and fancurvectl's messages name; the app has its own names.
public enum SmoothingField: String, CaseIterable, Sendable {
    case up = "upPercentPerSecond"
    case hold = "holdSeconds"
    case down = "downPercentPerSecond"
    case deadband = "deadbandPercent"
}

public struct Smoothing: Codable, Equatable, Sendable {
    public var upPercentPerSecond: Double
    public var holdSeconds: Double
    public var downPercentPerSecond: Double
    public var deadbandPercent: Double

    public init(upPercentPerSecond: Double = 25, holdSeconds: Double = 20,
                downPercentPerSecond: Double = 2, deadbandPercent: Double = 3) {
        self.upPercentPerSecond = upPercentPerSecond
        self.holdSeconds = holdSeconds
        self.downPercentPerSecond = downPercentPerSecond
        self.deadbandPercent = deadbandPercent
    }

    /// What `validate()` accepts for each field.
    public static func range(for field: SmoothingField) -> ClosedRange<Double> {
        switch field {
        case .up: return 1...100
        case .hold: return 0...120
        case .down: return 0.5...50
        case .deadband: return 0...10
        }
    }

    public func validate() throws {
        try Self.check(upPercentPerSecond, .up)
        try Self.check(holdSeconds, .hold)
        try Self.check(downPercentPerSecond, .down)
        try Self.check(deadbandPercent, .deadband)
    }

    private static func check(_ value: Double, _ field: SmoothingField) throws {
        let range = range(for: field)
        guard value.isFinite, range.contains(value) else {
            throw ValidationError(.smoothingOutOfRange(field: field, value: value, range: range))
        }
    }
}

public struct GPUPolicyConfig: Codable, Equatable, Sendable {
    public var enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }
}

/// A curve the user can switch off. JSON: {"enabled": true, "points": [[x, y], ...]}.
public struct AuxCurve: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var curve: Curve

    public init(enabled: Bool, curve: Curve) {
        self.enabled = enabled
        self.curve = curve
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case curve = "points"
    }
}

/// Both fans follow one curve on the hotter die, CPU or Radeon. The watts curve starts the fans before
/// the heat reaches the dies; the chassis curve is off by default, because on battery the fans barely
/// move the chassis temperature.
public struct CurveSet: Codable, Equatable, Sendable {
    public var hotspot: Curve
    public var power: AuxCurve
    public var chassis: AuxCurve

    public init(hotspot: Curve, power: AuxCurve, chassis: AuxCurve) {
        self.hotspot = hotspot
        self.power = power
        self.chassis = chassis
    }

    /// Switched-off curves are validated too, so switching one on can never apply a broken curve.
    public func validate() throws {
        try hotspot.validate(as: .hotspot)
        try power.curve.validate(as: .power)
        try chassis.curve.validate(as: .chassis)
    }
}

public struct Config: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var enabled: Bool
    public var curves: CurveSet
    public var smoothing: Smoothing
    public var gpuPolicy: GPUPolicyConfig

    public init(version: Int = Config.currentVersion, enabled: Bool = true, curves: CurveSet,
                smoothing: Smoothing = Smoothing(), gpuPolicy: GPUPolicyConfig = GPUPolicyConfig()) {
        self.version = version
        self.enabled = enabled
        self.curves = curves
        self.smoothing = smoothing
        self.gpuPolicy = gpuPolicy
    }

    /// Checked by replaying traces/stock-load.csv: hotspot stays at 0% at idle and ramps early under
    /// load; power starts at 23 W, 5 W above the settled-idle 95th percentile (17.35 W); chassis is
    /// off (see CurveSet).
    public static let defaults = Config(curves: CurveSet(
        hotspot: Curve([CurvePoint(60, 0), CurvePoint(72, 30), CurvePoint(82, 70), CurvePoint(88, 100)]),
        power: AuxCurve(enabled: true, curve: Curve([
            CurvePoint(23, 0), CurvePoint(38, 30), CurvePoint(58, 65), CurvePoint(78, 100),
        ])),
        chassis: AuxCurve(enabled: false, curve: Curve([
            CurvePoint(42, 0), CurvePoint(46, 35), CurvePoint(50, 75), CurvePoint(53, 100),
        ]))
    ))

    public func validate() throws {
        guard version == Config.currentVersion else {
            throw ValidationError(message: "unknown config version: \(version)")
        }
        try curves.validate()
        try smoothing.validate()
    }

    /// Decodes and validates; every failure is reported as ValidationError, naming the key at fault
    /// rather than dumping Swift's DecodingError.
    public static func decode(_ data: Data) throws -> Config {
        let config: Config
        do {
            config = try JSONDecoder().decode(Config.self, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            throw ValidationError(message: "the config does not parse: \(path(context.codingPath + [key])) is missing")
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context),
                let DecodingError.dataCorrupted(context) {
            let location = path(context.codingPath)
            throw ValidationError(message: "the config does not parse: \(location.isEmpty ? "" : location + ": ")\(context.debugDescription)")
        } catch {
            throw ValidationError(message: "the config does not parse: \(error)")
        }
        try config.validate()
        return config
    }

    /// A coding path as the keys read in the file, e.g. "smoothing.holdSeconds".
    private static func path(_ codingPath: [CodingKey]) -> String {
        codingPath.map(\.stringValue).joined(separator: ".")
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
