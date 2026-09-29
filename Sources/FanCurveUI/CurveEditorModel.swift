import FanCurveCore

/// The curve editor's draft. Every edit keeps the curve valid, so an invalid curve cannot be built
/// in the editor: points stay ordered with at least `minimumGap` between them, y never falls as x
/// grows, x stays in the curve's range, y in 0…100, and there are 2 to 8 points.
public struct CurveEditorModel: Equatable, Sendable {
    /// Smallest distance between neighbouring points, °C or W.
    static let minimumGap = 1.0

    /// What the daemon has.
    private(set) var saved: Config
    /// What the editor shows; the daemon receives it only on Apply.
    private(set) var draft: Config
    public var kind: CurveKind = .hotspot {
        didSet {
            if kind != oldValue { selection = nil }
        }
    }
    public private(set) var selection: Int?

    public init(config: Config) {
        saved = config
        draft = config
    }

    public var points: [CurvePoint] { curve(kind).points }

    public func curve(_ kind: CurveKind) -> Curve {
        switch kind {
        case .hotspot: return draft.curves.hotspot
        case .power: return draft.curves.power.curve
        case .chassis: return draft.curves.chassis.curve
        }
    }

    /// The hotspot curve is always on; the watts and chassis curves can be switched off.
    public var isEnabled: Bool {
        get {
            switch kind {
            case .hotspot: return true
            case .power: return draft.curves.power.enabled
            case .chassis: return draft.curves.chassis.enabled
            }
        }
        set {
            switch kind {
            case .hotspot: break
            case .power: draft.curves.power.enabled = newValue
            case .chassis: draft.curves.chassis.enabled = newValue
            }
        }
    }

    var smoothing: Smoothing {
        get { draft.smoothing }
        set { draft.smoothing = newValue }
    }

    public var isDirty: Bool {
        draft.curves != saved.curves || draft.smoothing != saved.smoothing
    }

    var canAdd: Bool { points.count < CurveLimits.maxPoints }
    public var canDelete: Bool { selection != nil && points.count > CurveLimits.minPoints }

    /// Why the draft cannot be applied, in the user's language; nil when it can.
    var validationMessage: String? {
        do {
            try draft.validate()
            return nil
        } catch let error as ValidationError {
            return UIText.validationMessage(for: error)
        } catch {
            return String(describing: error)
        }
    }

    public mutating func select(_ index: Int?) {
        selection = index.flatMap { points.indices.contains($0) ? $0 : nil }
    }

    /// Moves a point towards `proposed`, rounded to whole units and held between its neighbours.
    public mutating func movePoint(_ index: Int, to proposed: CurvePoint) {
        var points = self.points
        guard points.indices.contains(index) else { return }
        let range = CurveLimits.xRange(for: kind)
        let lowX = index > 0 ? points[index - 1].x + Self.minimumGap : range.lowerBound
        let highX = index < points.count - 1 ? points[index + 1].x - Self.minimumGap : range.upperBound
        let lowY = index > 0 ? points[index - 1].y : 0
        let highY = index < points.count - 1 ? points[index + 1].y : 100
        // Neighbours closer than two gaps (possible in a hand-written config) pin x in place.
        let x = lowX <= highX ? min(max(proposed.x.rounded(), lowX), highX) : points[index].x
        let y = min(max(proposed.y.rounded(), lowY), highY)
        points[index] = CurvePoint(x, y)
        setPoints(points)
        selection = index
    }

    /// Inserts a point at `proposed` (rounded) in x order, its y held between the neighbours'. Nil —
    /// nothing changes — when the curve is full, x is outside the curve's range or too close to a
    /// neighbour.
    @discardableResult
    public mutating func addPoint(at proposed: CurvePoint) -> Int? {
        guard canAdd else { return nil }
        let x = proposed.x.rounded()
        guard CurveLimits.xRange(for: kind).contains(x) else { return nil }
        var points = self.points
        let index = points.firstIndex { $0.x > x } ?? points.count
        if index > 0, x - points[index - 1].x < Self.minimumGap { return nil }
        if index < points.count, points[index].x - x < Self.minimumGap { return nil }
        let lowY = index > 0 ? points[index - 1].y : 0
        let highY = index < points.count ? points[index].y : 100
        points.insert(CurvePoint(x, min(max(proposed.y.rounded(), lowY), highY)), at: index)
        setPoints(points)
        selection = index
        return index
    }

    public mutating func deleteSelected() {
        guard canDelete, let index = selection else { return }
        var points = self.points
        points.remove(at: index)
        setPoints(points)
        selection = nil
    }

    /// Back to what the daemon has.
    public mutating func revert() {
        draft = saved
        selection = nil
    }

    /// The starting curves and smoothing; the daemon gets them on Apply.
    public mutating func resetToDefaults() {
        draft.curves = Config.defaults.curves
        draft.smoothing = Config.defaults.smoothing
        selection = nil
    }

    /// The daemon accepted `config`: it becomes both the saved state and the draft.
    public mutating func markApplied(_ config: Config) {
        saved = config
        draft = config
        select(selection)
    }

    /// The daemon accepted `config` after the draft had moved on: it becomes the saved state, and
    /// the draft keeps the newer edits.
    mutating func markSaved(_ config: Config) {
        saved = config
    }

    /// The chart's x range: a practical window for the curve, widened to every point with a margin
    /// and held inside the curve's valid range.
    public static func xDomain(for kind: CurveKind, points: [CurvePoint]) -> ClosedRange<Double> {
        let window: ClosedRange<Double>
        switch kind {
        case .hotspot: window = 30...105
        case .power: window = 0...120
        case .chassis: window = 25...65
        }
        let valid = CurveLimits.xRange(for: kind)
        let low = min(window.lowerBound, (points.map(\.x).min() ?? window.lowerBound) - 2)
        let high = max(window.upperBound, (points.map(\.x).max() ?? window.upperBound) + 2)
        return max(low, valid.lowerBound)...min(high, valid.upperBound)
    }

    /// The curve as drawn: flat before the first point and after the last, across the whole chart.
    public static func linePoints(_ points: [CurvePoint], domain: ClosedRange<Double>) -> [CurvePoint] {
        guard let first = points.first, let last = points.last else { return [] }
        var line = points
        if domain.lowerBound < first.x {
            line.insert(CurvePoint(domain.lowerBound, first.y), at: 0)
        }
        if domain.upperBound > last.x {
            line.append(CurvePoint(domain.upperBound, last.y))
        }
        return line
    }

    private mutating func setPoints(_ points: [CurvePoint]) {
        switch kind {
        case .hotspot: draft.curves.hotspot = Curve(points)
        case .power: draft.curves.power.curve = Curve(points)
        case .chassis: draft.curves.chassis.curve = Curve(points)
        }
    }
}
