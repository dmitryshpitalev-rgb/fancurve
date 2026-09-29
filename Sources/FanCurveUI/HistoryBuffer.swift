import FanCurveCore

/// The last hour of samples, sorted by time. The popup replaces it when it opens and
/// merges the newest samples on every poll while it stays open.
public struct HistoryBuffer: Equatable, Sendable {
    static let capacity = HistoryLimits.seconds

    public private(set) var samples: [Sample]

    public init(_ samples: [Sample] = []) {
        self.samples = Self.trimmed(samples.sorted { $0.t < $1.t })
    }

    public mutating func replace(with samples: [Sample]) {
        self.samples = Self.trimmed(samples.sorted { $0.t < $1.t })
    }

    /// Adds the samples newer than the last one kept; older or repeated ones are ignored.
    public mutating func merge(_ newer: [Sample]) {
        let last = samples.last?.t ?? -.infinity
        let fresh = newer.filter { $0.t > last }.sorted { $0.t < $1.t }
        guard !fresh.isEmpty else { return }
        samples = Self.trimmed(samples + fresh)
    }

    /// The samples of the last `seconds`, counted back from the latest sample.
    public func window(seconds: Double) -> [Sample] {
        guard let last = samples.last else { return [] }
        let start = last.t - seconds
        guard let first = samples.firstIndex(where: { $0.t >= start }) else { return [] }
        return Array(samples[first...])
    }

    private static func trimmed(_ samples: [Sample]) -> [Sample] {
        samples.count > capacity ? Array(samples.suffix(capacity)) : samples
    }
}
