import Foundation

/// Translates a German text into the language Kelter runs in.
///
/// The German text is the key; translations live in the app bundle's
/// `<language>.lproj/Localizable.strings` (in the repository:
/// `Resources/en.lproj/Localizable.strings`). Without a translation, or
/// without an app bundle (`swift run`), the German text is shown.
/// Placeholders follow `String(format:)`: `%@` for text, `%%` for a percent
/// sign in a text that has placeholders.
public func loc(_ key: String, _ arguments: CVarArg...) -> String {
    let template = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    return arguments.isEmpty ? template : String(format: template, arguments: arguments)
}

/// The languages Kelter can be switched to (Kelter → Einstellungen).
/// macOS picks an app's language at launch, so a change takes effect after
/// a restart.
public enum AppLanguage: String, CaseIterable, Sendable {
    /// Follow the language order of macOS.
    case system
    case german = "de"
    case english = "en"

    /// Kelter's own record of the choice.
    public static let choiceKey = "KelterLanguage"
    /// The macOS setting that makes an app start in a given language.
    public static let appleLanguagesKey = "AppleLanguages"

    public var displayName: String {
        switch self {
        case .system: return loc("Wie das System")
        case .german: return "Deutsch"
        case .english: return "English"
        }
    }

    /// The current choice.
    public static func current(defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: choiceKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Stores the choice and the matching macOS setting for the next start.
    public func apply(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.choiceKey)
        switch self {
        case .system:
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        case .german, .english:
            defaults.set([rawValue], forKey: Self.appleLanguagesKey)
        }
    }
}
