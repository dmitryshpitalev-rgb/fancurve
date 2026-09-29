import Foundation

/// The app's language: Russian or Ukrainian when the system language is one of them, English for
/// any other.
public enum Language: String, CaseIterable, Sendable {
    case ru, uk, en

    /// Decided by the first of the system's preferred languages: "uk-UA", "ru", "en-US", …
    static func forSystem(_ preferred: [String] = Locale.preferredLanguages) -> Language {
        guard let first = preferred.first?.lowercased().replacingOccurrences(of: "_", with: "-") else { return .en }
        if first == "ru" || first.hasPrefix("ru-") { return .ru }
        if first == "uk" || first.hasPrefix("uk-") { return .uk }
        return .en
    }
}
