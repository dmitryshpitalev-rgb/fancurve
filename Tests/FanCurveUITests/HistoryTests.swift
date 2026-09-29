import FanCurveCore
import Foundation
import Testing
@testable import FanCurveUI

func sample(_ t: Double, cpu: Double? = 60, gpu: Double? = 55, fans: [Double?] = [2000, 1900]) -> Sample {
    Sample(t: t, cpu: cpu, gpu: gpu, chassis: 38, power: 20, demandPercent: 10, leading: .hotspot,
           fanRPM: fans, mode: .active)
}

@Suite struct HistoryBufferTests {
    @Test func replaceSortsAndKeepsTheLastHour() {
        var buffer = HistoryBuffer()
        buffer.replace(with: (0..<4000).reversed().map { sample(Double($0)) })
        #expect(buffer.samples.count == HistoryBuffer.capacity)
        #expect(buffer.samples.first?.t == 400)
        #expect(buffer.samples.last?.t == 3999)
    }

    @Test func mergeAddsOnlyNewerSamples() {
        var buffer = HistoryBuffer([sample(10), sample(11), sample(12)])
        buffer.merge([sample(11), sample(12), sample(13), sample(14)])  // an overlapping delta
        #expect(buffer.samples.map(\.t) == [10, 11, 12, 13, 14])
        buffer.merge([sample(5)])
        #expect(buffer.samples.map(\.t) == [10, 11, 12, 13, 14])
    }

    @Test func mergeStaysWithinTheCapacity() {
        var buffer = HistoryBuffer((0..<3600).map { sample(Double($0)) })
        buffer.merge([sample(3600), sample(3601)])
        #expect(buffer.samples.count == HistoryBuffer.capacity)
        #expect(buffer.samples.first?.t == 2)
    }

    @Test func aWindowEndsAtTheLatestSample() {
        let buffer = HistoryBuffer((0..<3600).map { sample(Double($0)) })
        let five = buffer.window(seconds: ChartWindow.five.seconds)
        #expect(five.first?.t == 3299)
        #expect(five.last?.t == 3599)
        #expect(HistoryBuffer().window(seconds: 300).isEmpty)
    }
}

@Suite struct ChartSeriesTests {
    @Test func aMissingValueBreaksTheLine() {
        let samples = [sample(0, gpu: 50), sample(1, gpu: 51), sample(2, gpu: nil), sample(3, gpu: nil), sample(4, gpu: 53)]
        let points = ChartSeries.points(samples, series: .gpu) { $0.gpu }
        #expect(points.map(\.t) == [0, 1, 4])
        #expect(points.map(\.segment) == [0, 0, 1])
        #expect(Set(points.map(\.lineID)) == ["gpu#0", "gpu#1"])
    }

    @Test func aHoleInTimeBreaksTheLine() {
        let samples = [sample(0), sample(1), sample(10), sample(11)]
        let points = ChartSeries.points(samples, series: .cpu) { $0.cpu }
        #expect(points.map(\.segment) == [0, 0, 1, 1])
    }

    @Test func nonFiniteValuesAreSkipped() {
        let points = ChartSeries.points([sample(0, cpu: .nan), sample(1, cpu: 60)], series: .cpu) { $0.cpu }
        #expect(points.map(\.t) == [1])
    }

    @Test func theFanSeriesFollowsTheFasterFan() {
        let ranges = [FanRange(minRPM: 1836, maxRPM: 5616), FanRange(minRPM: 1700, maxRPM: 5200)]
        let value = ChartSeries.fanPercent(sample(0, fans: [3726, 3800]), ranges: ranges)
        #expect(abs((value ?? 0) - 60) < 0.01)  // right fan: (3800 - 1700) / 3500
        #expect(ChartSeries.fanPercent(sample(0, fans: [nil, nil]), ranges: ranges) == nil)
    }

    @Test func nearestPicksTheClosestSample() {
        let samples = (0..<10).map { sample(Double($0)) }
        #expect(ChartSeries.nearest(samples, to: 4.4)?.t == 4)
        #expect(ChartSeries.nearest(samples, to: 40)?.t == 9)
        #expect(ChartSeries.nearest([], to: 1) == nil)
    }

    @Test func windowsAreFiveFifteenAndSixtyMinutes() {
        #expect(ChartWindow.allCases.map(\.seconds) == [300, 900, 3600])
        #expect(UIText.Table(.ru).chartWindow(minutes: 5) == "5 мин")
    }

    @Test func aShortLineIsDrawnAsIs() {
        let points = ChartSeries.points((0..<300).map { sample(Double($0)) }, series: .cpu) { $0.cpu }
        #expect(ChartSeries.reduced(points) == points)
    }

    @Test func aLongLineKeepsItsSpikesWithinTheBudget() {
        var samples = (0..<3600).map { sample(Double($0), cpu: 60) }
        samples[1234] = sample(1234, cpu: 97)  // a spike near the 95° threshold
        samples[2345] = sample(2345, cpu: 41)
        let reduced = ChartSeries.reduced(ChartSeries.points(samples, series: .cpu) { $0.cpu })
        #expect(reduced.count <= ChartSeries.maxPointsPerLine)
        #expect(reduced.contains { $0.t == 1234 && $0.value == 97 })
        #expect(reduced.contains { $0.t == 2345 && $0.value == 41 })
        #expect(zip(reduced, reduced.dropFirst()).allSatisfy { $0.t < $1.t })
    }

    /// Buckets are anchored to absolute time: a window that slides by a second keeps its points,
    /// but for the first and the last bucket, so the redrawn line does not shimmer.
    @Test func aSlidingWindowKeepsItsPoints() {
        let samples = (0..<3601).map { sample(Double($0), cpu: 60 + 10 * sin(Double($0) / 37)) }
        let before = ChartSeries.reduced(ChartSeries.points(Array(samples[0..<3600]), series: .cpu) { $0.cpu })
        let after = ChartSeries.reduced(ChartSeries.points(Array(samples[1...]), series: .cpu) { $0.cpu })
        func inner(_ points: [ChartPoint]) -> [ChartPoint] { points.filter { $0.t >= 100 && $0.t < 3500 } }
        #expect(inner(before).count > 200)
        #expect(inner(before) == inner(after))
    }

    @Test func linesAreReducedSeparatelyAndKeepTheirBreaks() {
        let samples = (0..<2000).map { sample(Double($0), gpu: $0 < 1000 || $0 > 1100 ? 55 : nil) }
        let reduced = ChartSeries.reduced(ChartSeries.points(samples, series: .gpu) { $0.gpu })
        #expect(Set(reduced.map(\.lineID)) == ["gpu#0", "gpu#1"])
        let first = reduced.filter { $0.lineID == "gpu#0" }
        #expect(first.count <= ChartSeries.maxPointsPerLine)
        #expect(first.allSatisfy { $0.t < 1000 })
        #expect(reduced.filter { $0.lineID == "gpu#1" }.allSatisfy { $0.t > 1100 })
    }
}
