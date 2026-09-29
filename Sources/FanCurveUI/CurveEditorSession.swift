import Combine
import FanCurveCore
import Foundation

/// Loads the config into the editor, sends the draft on Apply, shows what happened. Used from
/// the main thread.
public final class CurveEditorSession: ObservableObject {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// How an Apply ended, or why the draft cannot be applied.
    public enum Outcome: Equatable {
        case applied
        case failed(String)
    }

    @Published public private(set) var phase = Phase.loading
    @Published public var model = CurveEditorModel(config: .defaults)
    /// How the last Apply ended; nil until one does.
    @Published private(set) var outcome: Outcome?
    @Published private(set) var applying = false
    /// What is typed in each smoothing field. Every keystroke updates the draft, so a click on Apply
    /// sends what is typed; text that is not a number stays in the field and blocks applying.
    @Published public private(set) var smoothingTexts: [SmoothingField: String]

    private let link: DaemonLinking
    private let locale: Locale

    /// `locale` reads and writes the smoothing fields; tests pin it.
    public init(link: DaemonLinking, locale: Locale = .current) {
        self.link = link
        self.locale = locale
        smoothingTexts = SmoothingInput.texts(for: Config.defaults.smoothing, locale: locale)  // what `model` starts with
    }

    /// The first smoothing field whose text is not a number, if any.
    public var invalidSmoothingField: SmoothingField? {
        SmoothingField.allCases.first { SmoothingInput.parse(smoothingTexts[$0] ?? "", locale: locale) == nil }
    }

    /// Apply sends something: the config is loaded, the draft is changed and valid, every field is a
    /// number, and no Apply is on its way.
    public var canApply: Bool {
        phase == .ready && model.isDirty && !applying && invalidSmoothingField == nil && model.validationMessage == nil
    }

    /// What the editor shows under the chart: why the draft cannot be applied (a field that is not a
    /// number, an invalid draft), else how the last Apply ended. "Applied" goes away as soon as the
    /// draft changes again.
    public var status: Outcome? {
        if let field = invalidSmoothingField { return .failed(UIText.smoothingNotANumber(field)) }
        if let problem = model.validationMessage { return .failed(problem) }
        if outcome == .applied, model.isDirty { return nil }
        return outcome
    }

    public func load() {
        phase = .loading
        outcome = nil
        link.getConfig { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let config):
                self.model = CurveEditorModel(config: config)
                self.smoothingTexts = SmoothingInput.texts(for: config.smoothing, locale: self.locale)
                self.phase = .ready
            case .failure(let error):
                self.phase = .failed(UIText.actionFailed(error))
            }
        }
    }

    public func typeSmoothing(_ text: String, in field: SmoothingField) {
        smoothingTexts[field] = text
        if let value = SmoothingInput.parse(text, locale: locale) {
            model.smoothing[field] = value
        }
    }

    public func revert() {
        model.revert()
        smoothingTexts = SmoothingInput.texts(for: model.smoothing, locale: locale)
    }

    public func resetToDefaults() {
        model.resetToDefaults()
        smoothingTexts = SmoothingInput.texts(for: model.smoothing, locale: locale)
    }

    /// Sends the draft. The chart and the fields stay editable while it is on its way: an edit made
    /// meanwhile is kept, and the daemon's answer becomes only what is saved.
    public func apply() {
        guard canApply else { return }  // the status already shows why, if anything is wrong
        applying = true
        let sent = model.draft
        let typed = smoothingTexts
        link.setConfig(sent) { [weak self] result in
            guard let self else { return }
            self.applying = false
            switch result {
            case .success(let config):
                if self.model.draft == sent, self.smoothingTexts == typed {
                    self.model.markApplied(config)
                    self.smoothingTexts = SmoothingInput.texts(for: self.model.smoothing, locale: self.locale)
                } else {
                    self.model.markSaved(config)
                }
                self.outcome = .applied
            case .failure(let error):
                self.outcome = .failed(UIText.actionFailed(error))
            }
        }
    }
}
