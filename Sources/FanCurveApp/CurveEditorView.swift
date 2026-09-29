import AppKit
import Charts
import FanCurveCore
import FanCurveUI
import SwiftUI

/// The curve editor: drag points, click to add, Delete to remove. Nothing reaches the daemon before
/// Apply.
struct CurveEditorView: View {
    /// A point is hit within this distance of its centre: a larger area than the mark.
    private static let hitRadius: CGFloat = 12
    /// A press that travels less than this is a click: it selects or adds a point and moves nothing.
    private static let clickDistance: CGFloat = 3

    @ObservedObject var session: CurveEditorSession
    @ObservedObject var app: AppModel
    @State private var dragIndex: Int?
    @State private var hoverX: Double?
    @State private var smoothingExpanded: Bool
    @FocusState private var chartFocused: Bool

    init(session: CurveEditorSession, app: AppModel, expandSmoothing: Bool = false) {
        self.session = session
        self.app = app
        _smoothingExpanded = State(initialValue: expandSmoothing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch session.phase {
            case .loading:
                ProgressView(UIText.loading)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.critical)
                Button(UIText.reloadButton) { session.load() }
            case .ready:
                editor
            }
        }
        .padding(16)
        .frame(width: 580)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $session.model.kind) {
                    ForEach(CurveKind.allCases, id: \.self) { Text(UIText.editorTab($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(UIText.curvePicker)
                .frame(width: 300)
                Spacer()
                if session.model.kind != .hotspot {
                    Toggle(UIText.curveEnabled, isOn: $session.model.isEnabled).toggleStyle(.switch)
                }
            }
            Text(readout).font(.callout).monospacedDigit()
            chart
                .frame(height: 300)
                .opacity(session.model.isEnabled ? 1 : 0.45)
            HStack {
                Text(UIText.editorHint).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(UIText.deletePoint) { session.model.deleteSelected() }
                    .disabled(!session.model.canDelete)
            }
            DisclosureGroup(UIText.smoothingTitle, isExpanded: $smoothingExpanded) {
                smoothingFields.padding(.top, 6)
            }
            switch session.status {
            case .applied?:
                Text(UIText.applied).font(.callout).foregroundStyle(.secondary)
            case .failed(let why)?:
                // A status colour never speaks alone: the warning glyph goes with the message.
                Label(why, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Palette.critical)
            case nil:
                EmptyView()
            }
            HStack {
                Button(UIText.defaultsButton) { session.resetToDefaults() }
                Spacer()
                Button(UIText.revertButton) { session.revert() }
                    .disabled(!session.model.isDirty && session.invalidSmoothingField == nil)
                Button(UIText.applyButton) { session.apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!session.canApply)
            }
        }
    }

    // MARK: Chart

    private var chart: some View {
        let model = session.model
        let points = model.points
        let domain = CurveEditorModel.xDomain(for: model.kind, points: points)
        let line = CurveEditorModel.linePoints(points, domain: domain)
        return Chart {
            ForEach(Array(line.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value(UIText.editorInputValue, point.x), y: .value(UIText.editorOutputValue, point.y))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let hoverX {
                RuleMark(x: .value(UIText.editorInputValue, hoverX))
                    .foregroundStyle(Color.primary.opacity(0.15))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            if let live = liveValue {
                RuleMark(x: .value(UIText.editorInputValue, live.x))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value(UIText.editorInputValue, live.x), y: .value(UIText.editorOutputValue, live.y))
                    .symbol {
                        Circle().fill(Color.primary).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Palette.card, lineWidth: 2))
                    }
            }
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                PointMark(x: .value(UIText.editorInputValue, point.x), y: .value(UIText.editorOutputValue, point.y))
                    .symbol {
                        let side: CGFloat = index == model.selection ? 14 : 10
                        Circle().fill(Color.accentColor).frame(width: side, height: side)
                            .overlay(Circle().stroke(Palette.card, lineWidth: 2))
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...100)
        .chartXAxisLabel(UIText.editorAxis(model.kind), alignment: .center)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel(anchor: .top)  // centred under its tick: a point at 60 reads as 60
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text(UIText.editorYLabel(percent: percent, fan: leftFan))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag($0, proxy, geometry) }
                            .onEnded { endDrag($0, proxy, geometry) }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hoverX = chartPoint(location, proxy, geometry)?.x
                        case .ended: hoverX = nil
                        }
                    }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($chartFocused)
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            session.model.deleteSelected()
            return .handled
        }
    }

    private func chartPoint(_ location: CGPoint, _ proxy: ChartProxy, _ geometry: GeometryProxy) -> CurvePoint? {
        guard let plot = proxy.plotFrame else { return nil }
        let origin = geometry[plot].origin
        guard let x: Double = proxy.value(atX: location.x - origin.x),
              let y: Double = proxy.value(atY: location.y - origin.y) else { return nil }
        return CurvePoint(x, y)
    }

    /// The point under the pointer, if one is within `hitRadius`.
    private func pointIndex(near location: CGPoint, _ proxy: ChartProxy, _ geometry: GeometryProxy) -> Int? {
        guard let plot = proxy.plotFrame else { return nil }
        let origin = geometry[plot].origin
        var best: (index: Int, distance: CGFloat)?
        for (index, point) in session.model.points.enumerated() {
            guard let x = proxy.position(forX: point.x), let y = proxy.position(forY: point.y) else { continue }
            let distance = hypot(origin.x + x - location.x, origin.y + y - location.y)
            if distance <= Self.hitRadius, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        return best?.index
    }

    private func drag(_ value: DragGesture.Value, _ proxy: ChartProxy, _ geometry: GeometryProxy) {
        chartFocused = true
        if dragIndex == nil, let index = pointIndex(near: value.startLocation, proxy, geometry) {
            dragIndex = index
            session.model.select(index)
        }
        // A click selects without nudging: the point moves only once the pointer really travels.
        guard let index = dragIndex, hypot(value.translation.width, value.translation.height) >= Self.clickDistance,
              let point = chartPoint(value.location, proxy, geometry) else { return }
        session.model.movePoint(index, to: point)
    }

    private func endDrag(_ value: DragGesture.Value, _ proxy: ChartProxy, _ geometry: GeometryProxy) {
        defer { dragIndex = nil }
        guard dragIndex == nil, hypot(value.translation.width, value.translation.height) < Self.clickDistance,
              let point = chartPoint(value.location, proxy, geometry) else { return }
        if session.model.addPoint(at: point) == nil {
            session.model.select(nil)
        }
    }

    // MARK: Readouts

    private var leftFan: FanRange? {
        app.snapshot?.fans.first?.range
    }

    /// The input right now as the daemon filters it (the die that feeds the hotspot curve, the watts
    /// or the chassis) and where the edited curve puts it.
    private var liveValue: CurvePoint? {
        guard let snapshot = app.snapshot else { return nil }
        let input: Double?
        switch session.model.kind {
        case .hotspot: input = snapshot.demand.hotDie.flatMap { snapshot.filtered[$0] }
        case .power: input = snapshot.filtered.power
        case .chassis: input = snapshot.filtered.chassis
        }
        guard let input, input.isFinite else { return nil }
        return CurvePoint(input, session.model.curve(session.model.kind).evaluate(input))
    }

    private var readout: String {
        let kind = session.model.kind
        let curve = session.model.curve(kind)
        if let hoverX {
            return UIText.curveReadout(input: hoverX, output: curve.evaluate(hoverX), kind: kind, fan: leftFan)
        }
        if let live = liveValue {
            return UIText.liveReadout(input: live.x, output: live.y, kind: kind, fan: leftFan)
        }
        return " "
    }

    // MARK: Smoothing

    private var smoothingFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(SmoothingField.allCases, id: \.self) { field in
                GridRow {
                    Text(UIText.smoothingLabel(field))
                    // Text, not a number binding: a number field commits only on Return or when the
                    // focus leaves it, and a mouse click on Apply does neither.
                    TextField("", text: Binding(get: { session.smoothingTexts[field] ?? "" },
                                                set: { session.typeSmoothing($0, in: field) }))
                        .accessibilityLabel(UIText.smoothingLabel(field))
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Text(UIText.smoothingRange(field)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
