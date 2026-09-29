import AppKit
import Combine
import FanCurveCore
import Foundation
import Testing
@testable import FanCurveUI

@Suite struct FanIconGeometryTests {
    @Test func theLevelLightsFinsInFiveSteps() {
        #expect((0...5).map(FanIconGeometry.litFins) == [0, 6, 11, 17, 22, 28])
        #expect(FanIconGeometry.litFins(level: -1) == 0)
        #expect(FanIconGeometry.litFins(level: 9) == FanIconGeometry.finCount)
    }

    @Test func finsStartAtTheTopAndLeanClockwise() {
        let top = FanIconGeometry.fin(0)
        #expect(abs(top.root.x - 50) < 0.01)
        #expect(abs(top.root.y - (50 - FanIconGeometry.finInnerRadius)) < 0.01)  // straight up from the centre
        #expect(abs(hypot(top.tip.x - 50, top.tip.y - 50) - FanIconGeometry.finOuterRadius) < 0.01)
        #expect(top.tip.x > top.root.x)  // the tip leans clockwise, to the right of the root
        #expect(FanIconGeometry.fin(1).root.x > top.root.x)  // the next fin follows clockwise
        #expect(FanIconGeometry.fin(FanIconGeometry.finCount / 2).root.y > 50)  // half way round is the bottom
    }

    @Test func theGeometryMatchesTheDesignFile() throws {
        struct Fins: Decodable {
            var count: Int
            var innerRadius: Double
            var outerRadius: Double
            var width: Double
            var slantDegrees: Double
            var ghostAlpha: Double
        }
        struct Design: Decodable {
            var discRadius: Double
            var fins: Fins
            var litFinsPerLevel: [Int]
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/FanCurveUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let design = try JSONDecoder().decode(Design.self, from: Data(contentsOf: repoRoot.appendingPathComponent("docs/icon/fan-icon.json")))
        #expect(Double(FanIconGeometry.discRadius) == design.discRadius)
        #expect(FanIconGeometry.finCount == design.fins.count)
        #expect(Double(FanIconGeometry.finInnerRadius) == design.fins.innerRadius)
        #expect(Double(FanIconGeometry.finOuterRadius) == design.fins.outerRadius)
        #expect(Double(FanIconGeometry.finWidth) == design.fins.width)
        #expect(Double(FanIconGeometry.finSlantDegrees) == design.fins.slantDegrees)
        #expect(Double(FanIconGeometry.ghostAlpha) == design.fins.ghostAlpha)
        #expect((0...5).map(FanIconGeometry.litFins) == design.litFinsPerLevel)
    }
}

@Suite struct FanIconRendererTests {
    /// Draws the wheel 1:1 in view-box units (100×100 px) and returns the alpha at `point`
    /// (y down, like the SVG).
    func alpha(level: Int, dimmed: Bool = false, at point: (x: Int, y: Int)) -> Int {
        let side = 100
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                    bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: 0, y: CGFloat(side))
            context.scaleBy(x: 1, y: -1)
            FanIconRenderer.drawWheel(level: level, alpha: dimmed ? FanIconRenderer.dimmedAlpha : 1, in: context,
                                      rect: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return Int(pixels[(point.y * side + point.x) * 4 + 3])
    }

    /// The pixel in the middle of fin `index`.
    func finPixel(_ index: Int) -> (x: Int, y: Int) {
        let fin = FanIconGeometry.fin(index)
        return (Int(((fin.root.x + fin.tip.x) / 2).rounded(.down)), Int(((fin.root.y + fin.tip.y) / 2).rounded(.down)))
    }

    @Test func theDiscIsAlwaysDrawnAndTheGapsStayEmpty() {
        #expect(alpha(level: 0, at: (50, 50)) == 255)  // the disc
        #expect(alpha(level: 5, at: (57, 10)) == 0)    // the gap between the first two fins
        #expect(alpha(level: 5, at: (50, 1)) == 0)     // outside the wheel
    }

    @Test func finsLightClockwiseFromTheTopAndTheRestStayGhosted() {
        let ghost = Int((255 * FanIconGeometry.ghostAlpha).rounded())
        #expect(abs(alpha(level: 0, at: finPixel(0)) - ghost) <= 2)  // the top fin, unlit
        #expect(alpha(level: 1, at: finPixel(0)) == 255)             // lit by the first level
        // Level 1 lights six fins: the seventh is still a ghost, level 2 lights it.
        #expect(abs(alpha(level: 1, at: finPixel(6)) - ghost) <= 2)
        #expect(alpha(level: 2, at: finPixel(6)) == 255)
        #expect(alpha(level: 5, at: finPixel(FanIconGeometry.finCount - 1)) == 255)
    }

    @Test func aDimmedWheelIsSemiTransparentGhostsIncluded() {
        let lit = alpha(level: 1, dimmed: true, at: finPixel(0))
        #expect(abs(lit - Int((255 * FanIconRenderer.dimmedAlpha).rounded())) <= 2)
        let ghost = alpha(level: 0, dimmed: true, at: finPixel(0))
        #expect(abs(ghost - Int((255 * FanIconRenderer.dimmedAlpha * FanIconGeometry.ghostAlpha).rounded())) <= 2)
    }

    @Test func theMenuBarImageIsATemplateWithTheTemperatureBesideIt() {
        let bare = FanIconRenderer.image(for: MenuBarIconState(level: 3, appearance: .normal, text: ""))
        let withText = FanIconRenderer.image(for: MenuBarIconState(level: 3, appearance: .normal, text: "72°"))
        #expect(bare.isTemplate)
        #expect(withText.isTemplate)
        #expect(bare.size == NSSize(width: 18, height: 18))
        #expect(withText.size.width > 30)
        #expect(withText.size.height == 18)
        #expect(withText.accessibilityDescription == UIText.menuBarAccessibility)
    }

    @Test func theAlertIsARedTriangleNotATemplate() {
        let alert = FanIconRenderer.image(for: MenuBarIconState(level: 0, appearance: .alert, text: ""))
        #expect(!alert.isTemplate)
        #expect(alert.size.width > 0)
        #expect(alert.accessibilityDescription == UIText.menuBarAlertAccessibility)
    }
}

@Suite struct MenuBarIconStateTests {
    @Test func anActiveDaemonShowsTheFasterFanAndTheHotDie() {
        // Both fans at 48% of their range: level 3 (40-60%).
        let state = MenuBarIconState.initial.next(makeSnapshot())
        #expect(state == MenuBarIconState(level: 3, appearance: .normal, text: "77°"))
    }

    @Test func macOSInChargeDimsTheWheel() {
        for mode: Mode in [.starting, .released(.sleep), .released(.sensorLoss), .disabled] {
            #expect(MenuBarIconState.initial.next(makeSnapshot(mode: mode)).appearance == .dimmed)
        }
    }

    @Test func safeModeAndASilentDaemonRaiseTheAlert() {
        let safe = MenuBarIconState.initial.next(makeSnapshot(mode: .safe(.crashLoop)))
        #expect(safe.appearance == .alert)
        #expect(safe.text == "")
        let before = MenuBarIconState(level: 4, appearance: .normal, text: "80°")
        #expect(before.next(nil) == MenuBarIconState(level: 4, appearance: .alert, text: ""))
    }

    @Test func theLevelKeepsItsHysteresis() {
        func fans(percent: Double) -> [FanState] {
            let range = FanRange(minRPM: 1836, maxRPM: 5616)
            return [FanState(actualRPM: Double(range.rpm(forPercent: percent)), targetRPM: nil, minRPM: 1836, maxRPM: 5616)]
        }
        let three = MenuBarIconState(level: 3, appearance: .normal, text: "")
        #expect(three.next(makeSnapshot(fans: fans(percent: 39))).level == 3)  // within 2% of the 40% edge
        #expect(three.next(makeSnapshot(fans: fans(percent: 37))).level == 2)
    }

    @Test func aMissingTachometerCountsAsZero() {
        let silent = [FanState(actualRPM: nil, targetRPM: nil, minRPM: 1836, maxRPM: 5616)]
        #expect(MenuBarIconState.fanPercent(makeSnapshot(fans: silent)) == nil)
        #expect(MenuBarIconState.initial.next(makeSnapshot(fans: silent)).level == 0)
    }

    @Test func theModelPublishesOnlyRealChanges() {
        let model = MenuBarIconModel()
        var published: [MenuBarIconState] = []
        let subscription = model.$state.sink { published.append($0) }
        model.update(with: makeSnapshot())
        model.update(with: makeSnapshot())  // same picture: no new value
        model.update(with: nil)
        subscription.cancel()
        #expect(published.count == 3)  // the initial value, then two real changes
    }
}
