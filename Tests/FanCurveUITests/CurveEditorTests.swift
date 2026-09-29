import FanCurveCore
import FanCurveIPC
import Foundation
import Testing
@testable import FanCurveUI

@Suite struct CurveEditorModelTests {
    func model() -> CurveEditorModel {
        CurveEditorModel(config: .defaults)  // hotspot: 60→0, 72→30, 82→70, 88→100
    }

    @Test func aDraggedPointStaysBetweenItsNeighbours() {
        var editor = model()
        editor.movePoint(1, to: CurvePoint(95.4, 90.2))  // past the next point, above its y
        #expect(editor.points[1] == CurvePoint(81, 70))
        editor.movePoint(1, to: CurvePoint(40, -5))
        #expect(editor.points[1] == CurvePoint(61, 0))
        editor.movePoint(1, to: CurvePoint(70.6, 25.4))
        #expect(editor.points[1] == CurvePoint(71, 25))
        #expect(editor.selection == 1)
    }

    @Test func theEndsStayInsideTheCurvesRange() {
        var editor = model()
        editor.movePoint(0, to: CurvePoint(5, 0))
        #expect(editor.points[0].x == 20)  // hotspot x: 20…110
        editor.movePoint(3, to: CurvePoint(140, 120))
        #expect(editor.points[3] == CurvePoint(110, 100))
        editor.kind = .power
        editor.movePoint(3, to: CurvePoint(260, 100))
        #expect(editor.points[3].x == 200)  // watts x: 0…200
    }

    @Test func aNewPointGoesInOrderAndFitsBetweenItsNeighbours() {
        var editor = model()
        let index = editor.addPoint(at: CurvePoint(77.3, 95))
        #expect(index == 2)
        #expect(editor.points[2] == CurvePoint(77, 70))  // y capped by the next point
        #expect(editor.selection == 2)
        #expect(editor.addPoint(at: CurvePoint(72.4, 40)) == nil)  // too close to 72
        #expect(editor.addPoint(at: CurvePoint(10, 0)) == nil)  // outside 20…110
    }

    @Test func pointsStayBetweenTwoAndEight() {
        var editor = model()
        for x in [62.0, 64, 66, 68] {
            #expect(editor.addPoint(at: CurvePoint(x, 5)) != nil)
        }
        #expect(editor.points.count == 8)
        #expect(!editor.canAdd)
        #expect(editor.addPoint(at: CurvePoint(90, 100)) == nil)

        var small = CurveEditorModel(config: .defaults)
        small.select(0)
        small.deleteSelected()
        small.select(0)
        small.deleteSelected()
        #expect(small.points.count == 2)
        small.select(0)
        #expect(!small.canDelete)
        small.deleteSelected()
        #expect(small.points.count == 2)
    }

    @Test func switchingOnAndOff() {
        var editor = model()
        #expect(editor.isEnabled)
        editor.isEnabled = false  // the hotspot curve cannot be switched off
        #expect(editor.isEnabled)
        #expect(!editor.isDirty)
        editor.kind = .chassis
        #expect(!editor.isEnabled)
        editor.isEnabled = true
        #expect(editor.draft.curves.chassis.enabled)
        #expect(editor.isDirty)
    }

    @Test func changingTheCurveClearsTheSelection() {
        var editor = model()
        editor.select(2)
        editor.kind = .power
        #expect(editor.selection == nil)
    }

    @Test func revertDefaultsAndApply() {
        var editor = model()
        editor.movePoint(1, to: CurvePoint(70, 20))
        editor.smoothing.holdSeconds = 30
        #expect(editor.isDirty)
        editor.revert()
        #expect(!editor.isDirty)
        #expect(editor.draft == Config.defaults)

        var custom = Config.defaults
        custom.curves.hotspot = Curve([CurvePoint(50, 10), CurvePoint(90, 100)])
        var loaded = CurveEditorModel(config: custom)
        loaded.resetToDefaults()
        #expect(loaded.draft.curves == Config.defaults.curves)
        #expect(loaded.isDirty)
        loaded.markApplied(loaded.draft)
        #expect(!loaded.isDirty)
        #expect(loaded.saved.curves == Config.defaults.curves)
    }

    @Test func badSmoothingIsReportedBeforeApplying() {
        var editor = model()
        #expect(editor.validationMessage == nil)
        editor.smoothing.holdSeconds = 500
        let tooLong = ValidationError(.smoothingOutOfRange(field: .hold, value: 500, range: 0...120))
        #expect(editor.validationMessage == UIText.validationMessage(for: tooLong))
    }

    @Test func anyEditLeavesAValidCurve() {
        var editor = model()
        let moves: [(Int, CurvePoint)] = [(0, CurvePoint(99, 99)), (3, CurvePoint(0, 0)), (2, CurvePoint(61, 100)),
                                          (1, CurvePoint(200, -50)), (0, CurvePoint(-10, 150))]
        for (index, point) in moves {
            editor.movePoint(index, to: point)
            #expect(editor.validationMessage == nil)
        }
        for x in stride(from: 21.0, through: 109, by: 11) {
            editor.addPoint(at: CurvePoint(x, x))
            #expect(editor.validationMessage == nil)
        }
    }

    @Test func theChartShowsTheWholeCurveWithMargins() {
        let hotspot = CurveEditorModel.xDomain(for: .hotspot, points: Config.defaults.curves.hotspot.points)
        #expect(hotspot == 30...105)
        let far = CurveEditorModel.xDomain(for: .hotspot, points: [CurvePoint(22, 0), CurvePoint(110, 100)])
        #expect(far == 20...110)
        let line = CurveEditorModel.linePoints([CurvePoint(60, 0), CurvePoint(88, 100)], domain: 30...105)
        #expect(line == [CurvePoint(30, 0), CurvePoint(60, 0), CurvePoint(88, 100), CurvePoint(105, 100)])
    }
}

@Suite struct CurveEditorSessionTests {
    let russian = Locale(identifier: "ru_RU")

    @Test func loadAndApply() {
        let link = PreviewLink()
        let session = CurveEditorSession(link: link, locale: russian)
        #expect(session.phase == .loading)
        session.load()
        #expect(session.phase == .ready)
        #expect(!session.canApply)
        session.apply()  // nothing changed: nothing is sent
        #expect(session.outcome == nil)

        session.model.movePoint(1, to: CurvePoint(70, 20))
        #expect(session.canApply)
        session.apply()
        #expect(session.outcome == .applied)
        #expect(session.status == .applied)
        #expect(!session.model.isDirty)
        #expect(link.config.curves.hotspot.points[1] == CurvePoint(70, 20))
        session.model.movePoint(1, to: CurvePoint(71, 21))
        #expect(session.status == nil)  // “Applied” no longer describes the draft
    }

    @Test func anInvalidDraftIsNotSent() {
        let link = PreviewLink()
        let session = CurveEditorSession(link: link, locale: russian)
        session.load()
        session.model.smoothing.downPercentPerSecond = 0
        #expect(!session.canApply)
        session.apply()
        let tooSlow = ValidationError(.smoothingOutOfRange(field: .down, value: 0, range: 0.5...50))
        #expect(session.status == .failed(UIText.validationMessage(for: tooSlow)))
        #expect(session.outcome == nil)  // nothing was sent, so there is no result to report
        #expect(link.config == .defaults)
    }

    @Test func aSilentDaemonIsShown() {
        let session = CurveEditorSession(link: UnreachableLink())
        session.load()
        guard case .failed(let message) = session.phase else {
            Issue.record("expected a failure, got \(session.phase)")
            return
        }
        #expect(message == UIText.connectionProblem(SocketError.system(call: "connect", code: ENOENT)))
    }

    @Test func aDaemonRefusalIsShownAndTheDraftStays() {
        let link = ScriptedLink()
        let session = CurveEditorSession(link: link, locale: russian)
        session.load()
        session.model.movePoint(1, to: CurvePoint(70, 20))
        session.apply()
        link.answerSetConfig(.failure(DaemonError.remote("could not apply the config: disk full")))
        #expect(session.status == .failed("could not apply the config: disk full"))
        #expect(session.model.isDirty)  // the draft is not lost
        #expect(session.canApply)
    }

    @Test func anEditMadeWhileApplyingIsKept() {
        let link = ScriptedLink()
        let session = CurveEditorSession(link: link, locale: russian)
        session.load()
        session.model.movePoint(1, to: CurvePoint(70, 20))
        session.apply()
        #expect(session.applying)
        #expect(!session.canApply)  // one Apply at a time
        session.model.movePoint(1, to: CurvePoint(71, 21))  // while the config is on its way
        link.answerSetConfig(.success(link.sentConfigs[0]))
        #expect(!session.applying)
        #expect(session.model.points[1] == CurvePoint(71, 21))
        #expect(session.model.saved.curves.hotspot.points[1] == CurvePoint(70, 20))
        #expect(session.model.isDirty)
        #expect(session.status == nil)  // “Applied” describes what was sent, not the draft
        session.apply()
        link.answerSetConfig(.success(link.sentConfigs[1]))
        #expect(link.sentConfigs[1].curves.hotspot.points[1] == CurvePoint(71, 21))
        #expect(session.status == .applied)
        #expect(!session.model.isDirty)
    }

    @Test func aFieldEditedWhileApplyingKeepsItsText() {
        let link = ScriptedLink()
        let session = CurveEditorSession(link: link, locale: russian)
        session.load()
        session.typeSmoothing("30", in: .hold)
        session.apply()
        session.typeSmoothing("", in: .hold)  // emptied before typing a new value
        link.answerSetConfig(.success(link.sentConfigs[0]))
        #expect(session.smoothingTexts[.hold] == "")  // not written over with the value just applied
        #expect(session.status == .failed(UIText.smoothingNotANumber(.hold)))
    }

    @Test func typingASmoothingValueChangesTheDraftAtOnce() {
        let link = PreviewLink()
        let session = CurveEditorSession(link: link, locale: russian)
        session.load()
        #expect(session.smoothingTexts == [.up: "25", .hold: "20", .down: "2", .deadband: "3"])
        session.typeSmoothing("25", in: .hold)  // 20 → 25, no Return needed
        #expect(session.model.smoothing.holdSeconds == 25)
        #expect(session.model.isDirty)
        #expect(session.status == nil)
        session.apply()  // as a mouse click on Apply does
        #expect(link.config.smoothing.holdSeconds == 25)
        #expect(session.status == .applied)
    }

    @Test func aFieldThatIsNotANumberBlocksApplyingUntilItIsOne() {
        let link = PreviewLink()
        let session = CurveEditorSession(link: link, locale: russian)
        session.load()
        session.typeSmoothing("", in: .down)  // emptied before typing a new value
        #expect(session.model.smoothing.downPercentPerSecond == 2)  // the draft keeps the last number
        #expect(session.invalidSmoothingField == .down)
        #expect(session.status == .failed(UIText.smoothingNotANumber(.down)))
        #expect(!session.canApply)
        #expect(session.smoothingTexts[.down] == "")  // what was typed stays in the field
        session.typeSmoothing("0,", in: .down)
        session.apply()
        #expect(link.config == .defaults)  // nothing was sent: 0 is out of range
        session.typeSmoothing("0,5", in: .down)
        #expect(session.model.smoothing.downPercentPerSecond == 0.5)
        #expect(session.invalidSmoothingField == nil)
        #expect(session.status == nil)
    }

    @Test func aRegionWithItsOwnDigitsCanApply() {
        let link = PreviewLink()
        let session = CurveEditorSession(link: link, locale: Locale(identifier: "ar_SA"))
        session.load()
        #expect(session.smoothingTexts[.hold] == "٢٠")
        #expect(session.invalidSmoothingField == nil)
        session.typeSmoothing("٣٠", in: .hold)
        #expect(session.canApply)
        session.apply()
        #expect(link.config.smoothing.holdSeconds == 30)
    }

    @Test func revertAndDefaultsRewriteTheFields() {
        let session = CurveEditorSession(link: PreviewLink(), locale: russian)
        session.load()
        session.typeSmoothing("abc", in: .hold)
        #expect(session.invalidSmoothingField == .hold)
        session.revert()
        #expect(session.smoothingTexts[.hold] == "20")
        #expect(session.status == nil)
        session.typeSmoothing("40", in: .up)
        #expect(session.model.isDirty)
        session.resetToDefaults()
        #expect(session.smoothingTexts[.up] == "25")
        #expect(!session.model.isDirty)
    }
}

@Suite struct SmoothingInputTests {
    let russian = Locale(identifier: "ru_RU"), english = Locale(identifier: "en_US")

    @Test func aNumberParsesWithEitherDecimalSeparator() {
        for locale in [russian, english] {
            #expect(SmoothingInput.parse("0,5", locale: locale) == 0.5)
            #expect(SmoothingInput.parse("0.5", locale: locale) == 0.5)
            #expect(SmoothingInput.parse(" 20 ", locale: locale) == 20)
            #expect(SmoothingInput.parse("20.", locale: locale) == 20)
        }
    }

    @Test func anythingElseIsNotANumber() {
        for locale in [russian, english, Locale(identifier: "ar_SA")] {
            for text in ["", " ", "abc", "1,2,3", "inf", "nan", "1e400"] {
                #expect(SmoothingInput.parse(text, locale: locale) == nil, "\(text) \(locale.identifier)")
            }
        }
    }

    @Test func textIsShortAndRoundTrips() {
        #expect(SmoothingInput.text(20, locale: russian) == "20")
        #expect(SmoothingInput.text(0.5, locale: russian) == "0,5")
        #expect(SmoothingInput.text(0.5, locale: english) == "0.5")
        #expect(SmoothingInput.texts(for: Smoothing(), locale: russian) == [.up: "25", .hold: "20", .down: "2", .deadband: "3"])
        for locale in [russian, english] {
            #expect(SmoothingInput.parse(SmoothingInput.text(0.5, locale: locale), locale: locale) == 0.5)
            #expect(SmoothingInput.parse(SmoothingInput.text(2.25, locale: locale), locale: locale) == 2.25)
        }
    }

    /// Arabic and Persian Macs write numbers in their own digits: the fields load them that way and
    /// must read them back, or no edit could be applied.
    @Test func aLocaleWithItsOwnDigitsRoundTrips() {
        let arabic = Locale(identifier: "ar_SA")
        #expect(SmoothingInput.texts(for: Smoothing(), locale: arabic) == [.up: "٢٥", .hold: "٢٠", .down: "٢", .deadband: "٣"])
        #expect(SmoothingInput.text(0.5, locale: arabic) == "٠٫٥")
        for locale in [arabic, Locale(identifier: "fa_IR")] {
            for value in [25, 20, 2, 3, 0.5, 2.25] {
                let text = SmoothingInput.text(value, locale: locale)
                #expect(SmoothingInput.parse(text, locale: locale) == value, "\(text) \(locale.identifier)")
            }
        }
        #expect(SmoothingInput.parse("0,5", locale: arabic) == 0.5)  // Latin digits still work
    }
}
