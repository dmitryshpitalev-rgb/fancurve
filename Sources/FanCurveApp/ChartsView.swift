import Charts
import FanCurveCore
import FanCurveUI
import SwiftUI

/// Line colours: CPU, GPU and chassis get three hues chosen to stay apart from each other on the card
/// in light (#ffffff) and dark (#1e1e1e) mode; single-line panels are named by their title and drawn
/// in a neutral ink.
enum SeriesColor {
    static func color(_ series: ChartSeries, _ scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch series {
        case .cpu: return Color(hex: dark ? 0x3987e5 : 0x2a78d6)
        case .gpu: return Color(hex: dark ? 0xd95926 : 0xeb6834)
        case .chassis: return Color(hex: dark ? 0x199e70 : 0x1baf7a)
        // Opaque on purpose: Charts draws a long line in pieces, and a translucent colour would
        // darken every joint.
        case .fans, .power: return Color(hex: dark ? 0xc3c2b7 : 0x52514e)
        }
    }
}

/// Where the pointer is over the charts. `PopupView` owns it (see there); only the crosshairs and
/// the readout observe it.
final class ChartHover: ObservableObject {
    @Published var t: Double?
}

/// Three panels over one time axis (no dual axes): temperatures, fan speed, watts.
/// Hovering any panel moves one crosshair through all three and one readout above them.
struct ChartsView: View {
    let history: HistoryBuffer
    let ranges: [FanRange]
    let hover: ChartHover
    @State private var window = ChartWindow.fifteen
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let samples = history.window(seconds: window.seconds)
        let domain = timeDomain(samples)
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $window) {
                ForEach(ChartWindow.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(UIText.chartWindowPicker)
            .frame(width: 210)
            ChartReadout(samples: samples, ranges: ranges, hover: hover)
            panel(UIText.temperatureChart, legend: true, points: ChartSeries.reduced(temperaturePoints(samples)), domain: domain,
                  yDomain: temperatureScale(samples), threshold: ControllerLimits.criticalTemperature, showTimeAxis: false)
            panel(UIText.fanChart, legend: false,
                  points: ChartSeries.reduced(ChartSeries.points(samples, series: .fans) { ChartSeries.fanPercent($0, ranges: ranges) }),
                  domain: domain, yDomain: 0...100, threshold: nil, showTimeAxis: false)
            panel(UIText.powerChart, legend: false,
                  points: ChartSeries.reduced(ChartSeries.points(samples, series: .power) { $0.power }),
                  domain: domain, yDomain: 0...powerTop(samples), threshold: nil, showTimeAxis: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.card))
    }

    private func panel(_ title: String, legend: Bool, points: [ChartPoint], domain: ClosedRange<Date>,
                       yDomain: ClosedRange<Double>, threshold: Double?, showTimeAxis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                if legend {
                    Spacer()
                    legendKeys
                }
            }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value(UIText.chartTimeValue, point.date), y: .value(title, point.value),
                             series: .value(UIText.chartLineValue, point.lineID))
                        .foregroundStyle(SeriesColor.color(point.series, scheme))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if let threshold, yDomain.contains(threshold) {
                    RuleMark(y: .value(UIText.chartThresholdValue, threshold))
                        .foregroundStyle(Palette.critical.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, alignment: .trailing, spacing: 1) {
                            // A status colour never speaks alone: the warning glyph and the value go with it.
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.critical)
                                Text(UIText.temperature(threshold)).foregroundStyle(.secondary)
                            }
                            .font(.caption2)
                        }
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    if showTimeAxis {
                        AxisValueLabel(format: .dateTime.hour().minute(), anchor: timeLabelAnchor(value, domain: domain))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        // One label width in every panel, so the three plots share one time axis.
                        if let number = value.as(Double.self) {
                            Text(number, format: .number.precision(.fractionLength(0)))
                                .frame(width: 24, alignment: .trailing)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                CrosshairOverlay(proxy: proxy, hover: hover)
            }
            .frame(height: showTimeAxis ? 84 : 66)
        }
    }

    /// Centred under its tick; a tick close to either edge keeps its label inside the chart.
    private func timeLabelAnchor(_ value: AxisValue, domain: ClosedRange<Date>) -> UnitPoint {
        guard let date = value.as(Date.self) else { return .top }
        let margin = window.seconds / 12
        if domain.upperBound.timeIntervalSince(date) < margin { return .topTrailing }
        if date.timeIntervalSince(domain.lowerBound) < margin { return .topLeading }
        return .top
    }

    /// Line keys, not boxes: a short stroke of each line's colour beside its name.
    private var legendKeys: some View {
        HStack(spacing: 8) {
            ForEach(ChartSeries.temperatures, id: \.self) { series in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(SeriesColor.color(series, scheme))
                        .frame(width: 12, height: 2)
                    Text(UIText.seriesName(series)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func temperaturePoints(_ samples: [Sample]) -> [ChartPoint] {
        ChartSeries.points(samples, series: .cpu) { $0.cpu }
            + ChartSeries.points(samples, series: .gpu) { $0.gpu }
            + ChartSeries.points(samples, series: .chassis) { $0.chassis }
    }

    /// Ends at the latest sample; an empty history shows the last `window` up to now.
    private func timeDomain(_ samples: [Sample]) -> ClosedRange<Date> {
        let end = samples.last.map { Date(timeIntervalSince1970: $0.t) } ?? Date()
        return end.addingTimeInterval(-window.seconds)...end
    }

    /// The readings' span with a margin, in steps of 5°C, at least 20°C tall, and never past what a
    /// sensor can read.
    private func temperatureScale(_ samples: [Sample]) -> ClosedRange<Double> {
        var low = Double.infinity, high = -Double.infinity
        func include(_ value: Double?) {
            guard let value, value.isFinite else { return }
            low = min(low, value)
            high = max(high, value)
        }
        for sample in samples {
            include(sample.cpu)
            include(sample.gpu)
            include(sample.chassis)
        }
        guard low <= high else { return 30...100 }
        let valid = ChannelMath.temperatureRange
        let bottom = max(valid.lowerBound, ((low - 5) / 5).rounded(.down) * 5)
        let top = min(valid.upperBound, max(((high + 5) / 5).rounded(.up) * 5, bottom + 20))
        return bottom...top
    }

    private func powerTop(_ samples: [Sample]) -> Double {
        let high = samples.compactMap(\.power).filter(\.isFinite).max() ?? 0
        return max(60, ((high + 10) / 10).rounded(.up) * 10)
    }
}

/// Every value at the hovered moment, or at the latest sample. It observes the hover position, so
/// it redraws alone while the pointer moves.
private struct ChartReadout: View {
    let samples: [Sample]
    let ranges: [FanRange]
    @ObservedObject var hover: ChartHover

    var body: some View {
        Text(text)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var text: String {
        let sample = hover.t.flatMap { ChartSeries.nearest(samples, to: $0) } ?? samples.last
        guard let sample else { return " " }
        return UIText.readout(sample, fanPercent: ChartSeries.fanPercent(sample, ranges: ranges))
    }
}

/// One panel's crosshair and hover handling. Only the overlays and the readout observe the hover
/// position, so moving the pointer never recomputes the chart marks.
private struct CrosshairOverlay: View {
    let proxy: ChartProxy
    @ObservedObject var hover: ChartHover

    var body: some View {
        GeometryReader { geometry in
            let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let date: Date = proxy.value(atX: location.x - plot.origin.x) {
                                hover.t = date.timeIntervalSince1970
                            }
                        case .ended:
                            hover.t = nil
                        }
                    }
                if let t = hover.t, let x = proxy.position(forX: Date(timeIntervalSince1970: t)) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1, height: plot.height)
                        .offset(x: plot.origin.x + x, y: plot.origin.y)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
