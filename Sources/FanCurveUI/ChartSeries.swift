import FanCurveCore
import Foundation

/// The popup's time ranges.
public enum ChartWindow: Int, CaseIterable, Identifiable, Sendable {
    case five = 5
    case fifteen = 15
    case sixty = 60

    public var id: Int { rawValue }
    public var seconds: Double { Double(rawValue) * 60 }
    public var title: String { UIText.chartWindow(minutes: rawValue) }
}

/// One point of one line. `segment` grows at every break, so a chart draws each run as its own line
/// (`lineID`) and never bridges a hole with a straight segment.
public struct ChartPoint: Identifiable, Equatable, Sendable {
    /// A series at a moment: unique within a chart.
    public struct ID: Hashable, Sendable {
        public var series: ChartSeries
        public var t: Double
    }

    public var series: ChartSeries
    public var segment: Int
    public var t: Double
    public var value: Double

    public init(series: ChartSeries, segment: Int, t: Double, value: Double) {
        self.series = series
        self.segment = segment
        self.t = t
        self.value = value
    }

    public var id: ID { ID(series: series, t: t) }
    public var date: Date { Date(timeIntervalSince1970: t) }
    public var lineID: String { "\(series.rawValue)#\(segment)" }
}

/// The plotted values; the raw value names a line in `ChartPoint.lineID`.
public enum ChartSeries: String, CaseIterable, Sendable {
    case cpu, gpu, chassis, fans, power

    /// The temperature lines in legend order.
    public static let temperatures: [ChartSeries] = [.cpu, .gpu, .chassis]

    /// A hole longer than this (the daemon restarted, the Mac slept) breaks the line.
    static let maxGapSeconds = 3.0

    /// The most points a line is drawn with. A longer run is reduced to the lowest and the highest
    /// point of each time bucket, so spikes (and the approach to 95°) stay visible while a
    /// 60-minute chart stays cheap to draw. Above 300, so the 5-minute window (300 or 301 samples,
    /// with tick jitter) never flips between the raw line and a reduced one.
    static let maxPointsPerLine = 320

    /// `points` with every line (`lineID`) reduced to at most `maxPointsPerLine` points. Lines keep
    /// their order and their breaks; within a bucket the lowest and the highest point stay, in time
    /// order. Buckets are whole seconds wide and anchored to absolute time, so a window that slides
    /// by a second keeps every point but the first and the last bucket's. Lines within the budget are
    /// returned as they are.
    public static func reduced(_ points: [ChartPoint]) -> [ChartPoint] {
        var result: [ChartPoint] = []
        var start = points.startIndex
        while start < points.endIndex {
            var end = start + 1
            while end < points.endIndex, points[end].series == points[start].series,
                  points[end].segment == points[start].segment {
                end += 1
            }
            let line = points[start..<end]
            if line.count > maxPointsPerLine {
                result += buckets(line)
            } else {
                result += line
            }
            start = end
        }
        return result
    }

    /// The lowest and the highest point of each bucket. At most `maxPointsPerLine / 2` buckets: one
    /// fewer than that spans the line, and a line starting mid-bucket touches one more.
    private static func buckets(_ line: ArraySlice<ChartPoint>) -> [ChartPoint] {
        guard let first = line.first, let last = line.last else { return [] }
        let width = max(((last.t - first.t) / Double(maxPointsPerLine / 2 - 1)).rounded(.up), 1)
        var reduced: [ChartPoint] = []
        var bucket = (first.t / width).rounded(.down)
        var low = first, high = first
        func keep() {
            if low.t == high.t {
                reduced.append(low)
            } else {
                reduced += low.t < high.t ? [low, high] : [high, low]
            }
        }
        for point in line.dropFirst() {
            let key = (point.t / width).rounded(.down)
            if key != bucket {
                keep()
                bucket = key
                low = point
                high = point
            } else if point.value < low.value {
                low = point
            } else if point.value > high.value {
                high = point
            }
        }
        keep()
        return reduced
    }

    public static func points(_ samples: [Sample], series: ChartSeries, value: (Sample) -> Double?) -> [ChartPoint] {
        var points: [ChartPoint] = []
        var segment = 0
        var previous: Double?
        for sample in samples {
            guard let reading = value(sample), reading.isFinite else {
                if previous != nil {
                    segment += 1
                    previous = nil
                }
                continue
            }
            if let previous, sample.t - previous > maxGapSeconds {
                segment += 1
            }
            points.append(ChartPoint(series: series, segment: segment, t: sample.t, value: reading))
            previous = sample.t
        }
        return points
    }

    /// The faster fan's speed in % of its range at one sample, like the menubar icon.
    public static func fanPercent(_ sample: Sample, ranges: [FanRange]) -> Double? {
        FanRange.fasterPercent(rpm: sample.fanRPM, ranges: ranges)
    }

    /// The sample nearest to `t`, for the hover readout.
    public static func nearest(_ samples: [Sample], to t: Double) -> Sample? {
        samples.min { abs($0.t - t) < abs($1.t - t) }
    }
}
