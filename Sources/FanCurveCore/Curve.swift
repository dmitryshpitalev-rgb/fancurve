/// Why a config, a curve or a trace is refused. The app renders `kind` in the user's language;
/// the daemon and fancurvectl print `message`, English like the rest of what they say, naming curves
/// and smoothing fields by their config keys.
public struct ValidationError: Error, Equatable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable {
        case pointCount(curve: CurveKind, count: Int)
        /// Point numbers are 1-based, as the user counts them.
        case pointNotANumber(curve: CurveKind, index: Int)
        case xOutOfRange(curve: CurveKind, x: Double, range: ClosedRange<Double>)
        case yOutOfRange(curve: CurveKind, y: Double)
        case xNotIncreasing(curve: CurveKind, index: Int)
        case yDecreasing(curve: CurveKind, index: Int)
        case smoothingOutOfRange(field: SmoothingField, value: Double, range: ClosedRange<Double>)
        /// Anything else, in English: a config file that does not parse, an unknown version, a malformed trace.
        case other(String)
    }

    public let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public init(message: String) {
        kind = .other(message)
    }

    public var message: String {
        switch kind {
        case .pointCount(let curve, let count):
            return "\(curve.rawValue): needs \(CurveLimits.minPoints) to \(CurveLimits.maxPoints) points, has \(count)"
        case .pointNotANumber(let curve, let index):
            return "\(curve.rawValue): point \(index) is not a number"
        case .xOutOfRange(let curve, let x, let range):
            return "\(curve.rawValue): x=\(x) outside \(range.lowerBound)…\(range.upperBound)"
        case .yOutOfRange(let curve, let y):
            return "\(curve.rawValue): speed \(y)% outside 0…100"
        case .xNotIncreasing(let curve, let index):
            return "\(curve.rawValue): x must strictly increase (point \(index))"
        case .yDecreasing(let curve, let index):
            return "\(curve.rawValue): speed must not fall as x grows (point \(index))"
        case .smoothingOutOfRange(let field, let value, let range):
            return "\(field.rawValue): \(value) outside \(range.lowerBound)…\(range.upperBound)"
        case .other(let message):
            return message
        }
    }

    public var description: String { message }
}

public struct CurvePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// Encoded as a two-element JSON array: [x, y].
extension CurvePoint: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "a curve point must be [x, y]")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

/// The three curves: hotspot reads the hotter die, CPU or Radeon; power and chassis read their own
/// channel and can be switched off. The raw value is the config key.
public enum CurveKind: String, Codable, CaseIterable, Sendable {
    case hotspot, power, chassis
}

public enum CurveLimits {
    public static let minPoints = 2
    public static let maxPoints = 8

    public static func xRange(for kind: CurveKind) -> ClosedRange<Double> {
        kind == .power ? 0...200 : 20...110
    }
}

/// Piecewise-linear map from a channel value (°C or W) to fan output in percent.
public struct Curve: Equatable, Sendable {
    public var points: [CurvePoint]

    public init(_ points: [CurvePoint]) {
        self.points = points
    }

    /// Clamps to the first/last point outside the curve. Assumes a validated curve.
    public func evaluate(_ x: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        for index in 1..<points.count where x <= points[index].x {
            let a = points[index - 1]
            let b = points[index]
            return a.y + (x - a.x) / (b.x - a.x) * (b.y - a.y)
        }
        return last.y
    }

    public func validate(as kind: CurveKind) throws {
        guard (CurveLimits.minPoints...CurveLimits.maxPoints).contains(points.count) else {
            throw ValidationError(.pointCount(curve: kind, count: points.count))
        }
        let xRange = CurveLimits.xRange(for: kind)
        for (index, point) in points.enumerated() {
            guard point.x.isFinite, point.y.isFinite else {
                throw ValidationError(.pointNotANumber(curve: kind, index: index + 1))
            }
            guard xRange.contains(point.x) else {
                throw ValidationError(.xOutOfRange(curve: kind, x: point.x, range: xRange))
            }
            guard (0...100).contains(point.y) else {
                throw ValidationError(.yOutOfRange(curve: kind, y: point.y))
            }
            if index > 0 {
                let previous = points[index - 1]
                guard point.x > previous.x else {
                    throw ValidationError(.xNotIncreasing(curve: kind, index: index + 1))
                }
                guard point.y >= previous.y else {
                    throw ValidationError(.yDecreasing(curve: kind, index: index + 1))
                }
            }
        }
    }
}

/// Encoded as a JSON array of points.
extension Curve: Codable {
    public init(from decoder: Decoder) throws {
        points = try [CurvePoint](from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try points.encode(to: encoder)
    }
}
