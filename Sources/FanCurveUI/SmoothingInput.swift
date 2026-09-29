import FanCurveCore
import Foundation

/// The text of the editor's smoothing fields: what a typed value means, and how a value is shown, in
/// the locale's digits and decimal separator.
enum SmoothingInput {
    /// A finite number, typed with either decimal separator or as the locale writes it (in its own
    /// digits, too); nil for anything else.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: "."))
                ?? reader(for: locale).number(from: trimmed)?.doubleValue,
              value.isFinite else { return nil }
        return value
    }

    /// The value as the locale writes it, without trailing zeros: 20, 0,5 (ru_RU), 0.5 (en_US),
    /// ٠٫٥ (ar_SA).
    static func text(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(0...2)).grouping(.never))
    }

    static func texts(for smoothing: Smoothing, locale: Locale = .current) -> [SmoothingField: String] {
        Dictionary(uniqueKeysWithValues: SmoothingField.allCases.map { ($0, text(smoothing[$0], locale: locale)) })
    }

    /// Reads what `text` writes. Made when needed: only text that `Double` cannot read, such as
    /// another script's digits, gets this far.
    private static func reader(for locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter
    }
}

extension Smoothing {
    /// One field's value.
    subscript(field: SmoothingField) -> Double {
        get {
            switch field {
            case .up: return upPercentPerSecond
            case .hold: return holdSeconds
            case .down: return downPercentPerSecond
            case .deadband: return deadbandPercent
            }
        }
        set {
            switch field {
            case .up: upPercentPerSecond = newValue
            case .hold: holdSeconds = newValue
            case .down: downPercentPerSecond = newValue
            case .deadband: deadbandPercent = newValue
            }
        }
    }
}
