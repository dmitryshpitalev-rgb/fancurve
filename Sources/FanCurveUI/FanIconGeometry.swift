import CoreGraphics

/// The menubar wheel: this MacBook's blower wheel seen from above — a big flat disc and a fringe of
/// thin, slightly swept fins. Copied from docs/icon/fan-icon.json in a 100×100 view box; a test
/// keeps the two in sync.
enum FanIconGeometry {
    static let viewBox: CGFloat = 100
    static let center = CGPoint(x: 50, y: 50)
    static let discRadius: CGFloat = 30
    /// The real wheel has 48 fins; at 18 pt they would be thinner than a pixel.
    static let finCount = 28
    static let finInnerRadius: CGFloat = 34
    static let finOuterRadius: CGFloat = 47
    static let finWidth: CGFloat = 3.2
    /// A fin leans this far clockwise from its root to its tip.
    static let finSlantDegrees: CGFloat = 10
    /// Fins the level has not reached are drawn this transparent, so the wheel stays a wheel at 0.
    static let ghostAlpha: CGFloat = 0.28
    static let levels = 5

    /// How many fins `level` (0…5) lights: 0, 6, 11, 17, 22, 28.
    static func litFins(level: Int) -> Int {
        let clamped = min(max(level, 0), levels)
        return Int((Double(clamped) * Double(finCount) / Double(levels)).rounded())
    }

    /// Fin `index`, counted clockwise from the top: its root on the inner radius and its tip on the
    /// outer one (y down, like the SVG).
    static func fin(_ index: Int) -> (root: CGPoint, tip: CGPoint) {
        let start = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(finCount)
        let end = start + finSlantDegrees * .pi / 180
        return (CGPoint(x: center.x + finInnerRadius * cos(start), y: center.y + finInnerRadius * sin(start)),
                CGPoint(x: center.x + finOuterRadius * cos(end), y: center.y + finOuterRadius * sin(end)))
    }
}
