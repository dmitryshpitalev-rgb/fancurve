import AppKit
import CoreGraphics

/// Draws the menubar picture: the blower wheel with `level` of its fins lit and the
/// temperature next to it, as one template image — macOS tints it for a light or dark menu bar. The
/// alert is a red triangle and is not a template.
public enum FanIconRenderer {
    static let iconSize: CGFloat = 18
    /// Opacity of the wheel while macOS drives the fans.
    static let dimmedAlpha: CGFloat = 0.35
    static let textGap: CGFloat = 3
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

    public static func image(for state: MenuBarIconState) -> NSImage {
        if state.appearance == .alert {
            return alertImage()
        }
        let text = state.text as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = state.text.isEmpty ? .zero : text.size(withAttributes: attributes)
        let width = iconSize + (state.text.isEmpty ? 0 : textGap + ceil(textSize.width))
        let alpha = state.appearance == .dimmed ? dimmedAlpha : 1
        let image = NSImage(size: NSSize(width: width, height: iconSize), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            drawWheel(level: state.level, alpha: alpha, in: context,
                      rect: CGRect(x: 0, y: 0, width: iconSize, height: iconSize))
            if !state.text.isEmpty {
                text.draw(at: NSPoint(x: iconSize + textGap, y: (iconSize - textSize.height) / 2), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = UIText.menuBarAccessibility
        return image
    }

    /// The wheel in view-box units scaled into `rect` of a y-down context: the disc, then the fins
    /// clockwise from the top — lit up to the level, ghosted past it.
    static func drawWheel(level: Int, alpha: CGFloat, in context: CGContext, rect: CGRect) {
        let scale = min(rect.width, rect.height) / FanIconGeometry.viewBox
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: scale, y: scale)
        context.setAlpha(alpha)
        // One layer, so the dimmed alpha applies to the whole wheel once and the ghost fins keep
        // their own transparency inside it.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        let center = FanIconGeometry.center
        let disc = FanIconGeometry.discRadius
        context.fillEllipse(in: CGRect(x: center.x - disc, y: center.y - disc, width: disc * 2, height: disc * 2))
        context.setLineWidth(FanIconGeometry.finWidth)
        context.setLineCap(.butt)
        let lit = FanIconGeometry.litFins(level: level)
        for index in 0..<FanIconGeometry.finCount {
            context.setAlpha(index < lit ? 1 : FanIconGeometry.ghostAlpha)
            let fin = FanIconGeometry.fin(index)
            context.move(to: fin.root)
            context.addLine(to: fin.tip)
            context.strokePath()
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    static func alertImage() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white, .systemRed]))
        let symbol = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: UIText.menuBarAlertAccessibility)
            .flatMap { $0.withSymbolConfiguration(configuration) }
        let image = symbol ?? NSImage(size: NSSize(width: iconSize, height: iconSize))
        image.isTemplate = false
        return image
    }
}
