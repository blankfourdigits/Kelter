import Foundation
import KelterCore
import KelterWine

public enum SteamUIFixError: LocalizedError, Equatable {
    case missingFile(String)
    case prefixNotInitialized(String)
    case registryFailed(status: Int32)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let path):
            return loc("Für die Steam-Fensterkorrektur fehlt die Datei %@.", "\(path)")
        case .prefixNotInitialized(let path):
            return loc("Die Windows-Umgebung ist noch nicht eingerichtet (%@ fehlt).", "\(path)")
        case .registryFailed(let status):
            return loc("Die Steam-Fensterkorrektur konnte nicht in der Registrierung eingetragen werden (Status %@).", "\(status)")
        }
    }
}

/// Installs the helper library that makes Steam's window visible.
///
/// Background: see `RuntimeConfig.Steam.UIFix` and
/// `Tools/steam-ui-fix/winmm_proxy.c`. In short, the helper takes the place of
/// `winmm.dll` for `steamwebhelper.exe` only, forwards every call to Wine's
/// real winmm (kept as `winmm_orig.dll`) and adds Chromium switches to Steam's
/// browser process. No Steam file is touched, so Steam updates do not undo it.
public struct SteamUIFix: Sendable {
    /// The helper reads the switches to add from this variable.
    public static let environmentVariable = "KELTER_CEF_APPEND"

    static let registryKey = "HKCU\\Software\\Wine\\AppDefaults\\steamwebhelper.exe\\DllOverrides"
    static let markerFileName = "steam-ui-fix-registered"

    /// The prebuilt helper (`Resources/steam-ui-fix/winmm.dll`).
    public let helperLibrary: URL
    /// Wine's own `winmm.dll` inside the Wine installation.
    public let builtinLibrary: URL

    public init(helperLibrary: URL, builtinLibrary: URL) {
        self.helperLibrary = helperLibrary
        self.builtinLibrary = builtinLibrary
    }

    public init(config: RuntimeConfig.Steam.UIFix, resourcesDirectory: URL, wine: WineInstallation) {
        self.init(
            helperLibrary: resourcesDirectory.appendingPathComponent(config.library),
            builtinLibrary: wine.libDirectory.appendingPathComponent(config.builtinLibrary)
        )
    }

    // MARK: Environment

    /// The environment that tells the helper which switches to add. An empty
    /// list switches the helper off for this start.
    public static func environment(browserArguments: [String]) -> [String: String] {
        let value = browserArguments.isEmpty ? "-" : browserArguments.joined(separator: " ")
        return [environmentVariable: value]
    }

    // MARK: Installing

    static func system32(prefix: URL) -> URL {
        prefix
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("windows", isDirectory: true)
            .appendingPathComponent("system32", isDirectory: true)
    }

    static func marker(prefix: URL) -> URL {
        prefix.deletingLastPathComponent().appendingPathComponent(markerFileName)
    }

    /// Puts the two libraries into the bottle. Safe to repeat; it is done
    /// before every Steam start because Wine restores its own `winmm.dll`
    /// whenever it updates a prefix.
    public func installFiles(prefix: URL, fileManager: FileManager = .default) throws {
        for file in [helperLibrary, builtinLibrary] where !fileManager.fileExists(atPath: file.path) {
            throw SteamUIFixError.missingFile(file.path)
        }
        let system32 = Self.system32(prefix: prefix)
        guard fileManager.fileExists(atPath: system32.path) else {
            throw SteamUIFixError.prefixNotInitialized(system32.path)
        }
        try Self.replace(system32.appendingPathComponent("winmm_orig.dll"), with: builtinLibrary, fileManager: fileManager)
        try Self.replace(system32.appendingPathComponent("winmm.dll"), with: helperLibrary, fileManager: fileManager)
    }

    /// Files plus the registry entry that makes `steamwebhelper.exe` (and
    /// only it) load the helper instead of Wine's winmm.
    public func install(prefix: URL, settings: BottleSettings, runner: WineRunner) async throws {
        try installFiles(prefix: prefix)

        let marker = Self.marker(prefix: prefix)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let status = try await runner.run(
            ["reg", "add", Self.registryKey, "/v", "winmm", "/t", "REG_SZ", "/d", "native,builtin", "/f"],
            prefix: prefix,
            settings: settings
        )
        guard status == 0 else { throw SteamUIFixError.registryFailed(status: status) }
        try Data().write(to: marker)
    }

    /// Undoes `install`: Wine's own winmm is put back and the registry entry
    /// removed.
    public func remove(prefix: URL, settings: BottleSettings, runner: WineRunner) async throws {
        let fileManager = FileManager.default
        let system32 = Self.system32(prefix: prefix)
        if fileManager.fileExists(atPath: system32.path), fileManager.fileExists(atPath: builtinLibrary.path) {
            try Self.replace(system32.appendingPathComponent("winmm.dll"), with: builtinLibrary, fileManager: fileManager)
            try? fileManager.removeItem(at: system32.appendingPathComponent("winmm_orig.dll"))
        }
        let marker = Self.marker(prefix: prefix)
        if fileManager.fileExists(atPath: marker.path) {
            _ = try await runner.run(
                ["reg", "delete", Self.registryKey, "/v", "winmm", "/f"],
                prefix: prefix,
                settings: settings
            )
            try? fileManager.removeItem(at: marker)
        }
    }

    /// Whether the registry entry was written for this bottle.
    public static func isRegistered(prefix: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: marker(prefix: prefix).path)
    }

    /// Removes whatever is at `destination` (file or symbolic link, never its
    /// target) and copies `source` there.
    private static func replace(_ destination: URL, with source: URL, fileManager: FileManager) throws {
        // attributesOfItem does not follow symbolic links, so a link whose
        // target is gone is found (and removed) too.
        if (try? fileManager.attributesOfItem(atPath: destination.path)) != nil {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}
