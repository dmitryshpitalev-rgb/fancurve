/// A fan's controllable range: 0% is the stock minimum, 100% is F?Mx.
public struct FanRange: Codable, Equatable, Sendable {
    public var minRPM: Double
    public var maxRPM: Double

    public init(minRPM: Double, maxRPM: Double) {
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    /// A range the controller can drive: 0 < minRPM < maxRPM ≤ 100 000. No computer fan comes near
    /// that maximum; a bigger one is a garbage reading (a float key can read 3.4e38, or infinity),
    /// and `rpm(forPercent:)` would trap on it. Checked wherever a range comes from outside Core:
    /// state.json, the SMC, a `--simulate` profile.
    public var isUsable: Bool { minRPM > 0 && maxRPM > minRPM && maxRPM <= 100_000 }

    public func rpm(forPercent percent: Double) -> Int {
        let clamped = min(max(percent, 0), 100)
        return Int((minRPM + clamped / 100 * (maxRPM - minRPM)).rounded())
    }

    public func percent(forRPM rpm: Double) -> Double {
        guard maxRPM > minRPM else { return 0 }
        return min(max((rpm - minRPM) / (maxRPM - minRPM) * 100, 0), 100)
    }
}

extension FanRange {
    /// The faster fan's speed in % of its own range: readings pair with ranges by index, and
    /// non-finite readings count as missing. Nil when no reading is usable.
    public static func fasterPercent(rpm readings: [Double?], ranges: [FanRange]) -> Double? {
        zip(ranges, readings).compactMap { range, rpm -> Double? in
            guard let rpm, rpm.isFinite else { return nil }
            return range.percent(forRPM: rpm)
        }.max()
    }
}
