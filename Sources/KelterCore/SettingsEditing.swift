import Foundation

/// How Wine loads one library, as written in `WINEDLLOVERRIDES`.
public enum DllOverrideMode: String, CaseIterable, Codable, Sendable {
    case nativeThenBuiltin = "n,b"
    case builtinThenNative = "b,n"
    case native = "n"
    case builtin = "b"
    case disabled = "d"

    public var displayName: String {
        switch self {
        case .nativeThenBuiltin: return "Windows-Version, sonst Wines eigene"
        case .builtinThenNative: return "Wines eigene, sonst Windows-Version"
        case .native: return "Nur Windows-Version"
        case .builtin: return "Nur Wines eigene"
        case .disabled: return "Abgeschaltet"
        }
    }

    /// Reads a mode as Wine accepts it (`native,builtin`, `n, b`, empty for
    /// disabled …).
    public init?(wineValue: String) {
        let parts = wineValue.lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.prefix(1) }
        switch parts.joined(separator: ",") {
        case "n,b": self = .nativeThenBuiltin
        case "b,n": self = .builtinThenNative
        case "n": self = .native
        case "b": self = .builtin
        case "", "d": self = .disabled
        default: return nil
        }
    }
}

public enum SettingsEditingError: LocalizedError, Equatable {
    case invalidVariableName(String)
    case reservedVariable(String)
    case invalidLibraryName(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVariableName(let name):
            return "„\(name)“ ist kein gültiger Name für eine Umgebungsvariable. Erlaubt sind Buchstaben, Ziffern und _, nicht am Anfang eine Ziffer."
        case .reservedVariable(let name):
            return "\(name) setzt Kelter selbst für die Bottle und kann hier nicht geändert werden."
        case .invalidLibraryName(let name):
            return "„\(name)“ ist kein gültiger Bibliotheksname. Beispiele: d3d11, dxgi, winmm, steam.exe."
        }
    }
}

/// Checks and normalises what the user types into the bottle's editors.
public enum SettingsEditing {
    /// Variables Kelter sets itself and that would break the bottle if
    /// changed here. WINEDLLOVERRIDES has its own editor.
    public static let reservedVariables: Set<String> = ["WINEPREFIX", "WINEDLLOVERRIDES"]

    /// A valid environment variable name, trimmed.
    public static func variableName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = name.unicodeScalars.first,
              first == "_" || (first.isASCII && CharacterSet.letters.contains(first)),
              name.unicodeScalars.allSatisfy({ $0 == "_" || ($0.isASCII && CharacterSet.alphanumerics.contains($0)) })
        else { throw SettingsEditingError.invalidVariableName(name) }
        guard !reservedVariables.contains(name.uppercased()) else {
            throw SettingsEditingError.reservedVariable(name.uppercased())
        }
        return name
    }

    /// A library name as Wine expects it in overrides: lower case, without
    /// a `.dll` ending (other endings such as `.exe` stay).
    public static func libraryName(_ input: String) throws -> String {
        var name = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasSuffix(".dll") { name.removeLast(4) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-.")
        guard !name.isEmpty, !name.hasPrefix("."),
              name.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else { throw SettingsEditingError.invalidLibraryName(input.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return name
    }

    /// Sets (or replaces) a variable. Values may be empty.
    public static func setVariable(_ name: String, value: String, in settings: inout BottleSettings) throws {
        let name = try variableName(name)
        // A variable that differs only in case would be a second entry.
        for key in settings.environment.keys where key != name && key.uppercased() == name.uppercased() {
            settings.environment.removeValue(forKey: key)
        }
        settings.environment[name] = value
    }

    public static func setOverride(_ library: String, mode: DllOverrideMode, in settings: inout BottleSettings) throws {
        settings.dllOverrides[try libraryName(library)] = mode.rawValue
    }

    /// Entries sorted by name, for showing them in a stable order.
    public static func sorted(_ entries: [String: String]) -> [(key: String, value: String)] {
        entries
            .map { (key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }
}
