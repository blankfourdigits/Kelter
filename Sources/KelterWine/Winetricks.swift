import Foundation
import KelterCore

public enum WinetricksError: LocalizedError, Equatable {
    case invalidVerb(String)
    case missingTools([String])
    case failed(status: Int32)
    /// A Microsoft installer refused because a newer version is already
    /// there (exit code 1638, which Winetricks sees as 102).
    case alreadyNewer(installer: String)

    public var errorDescription: String? {
        switch self {
        case .invalidVerb(let verb):
            return loc("„%@“ ist kein gültiger Winetricks-Paketname.", "\(verb)")
        case .missingTools(let tools):
            return loc(
                "Winetricks braucht für viele Pakete %@. Einmalig im Terminal installieren:\n\nbrew install %@",
                tools.joined(separator: ", "), tools.joined(separator: " "))
        case .failed(let status):
            return loc("Winetricks meldet einen Fehler (Status %@). Die Einzelheiten stehen im Log.", "\(status)")
        case .alreadyNewer(let installer):
            return loc(
                "%@ ist in dieser Bottle bereits in einer neueren Version installiert, meist von Steam selbst. Es ist nichts zu tun. Weitere Pakete aus demselben Aufruf wurden nicht installiert; bitte einzeln installieren.",
                installer)
        }
    }
}

/// Winetricks: download, checks and the environment it runs with. Running
/// it goes through `WineRunner.runWinetricks`, like every other Wine call.
public enum Winetricks {
    /// Package names and settings Winetricks accepts, e.g. `vcrun2022` or
    /// `renderer=gl`.
    public static func validatedVerbs(_ input: [String]) throws -> [String] {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.=-")
        return try input
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { verb in
                guard !verb.hasPrefix("-"), verb.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                    throw WinetricksError.invalidVerb(verb)
                }
                return verb
            }
    }

    /// Turns a failed run into a clearer error where the cause is known
    /// from Winetricks' output.
    public static func explainFailure(status: Int32, output: String) -> WinetricksError {
        // Microsoft's installers end with 1638 ("a newer version is
        // installed"); the shell only passes on the low byte, 102.
        for line in output.split(separator: "\n") where line.contains("returned status 102") {
            if let range = line.range(of: #"vc_redist\.(x86|x64|arm64)\.exe"#, options: .regularExpression) {
                return .alreadyNewer(installer: "Visual C++ (\(line[range]))")
            }
        }
        return .failed(status: status)
    }

    /// Splits what the user typed ("vcrun2022 corefonts, xact") into verbs.
    public static func verbs(fromText text: String) throws -> [String] {
        try validatedVerbs(text.components(separatedBy: CharacterSet(charactersIn: " ,;\n\t")))
    }

    /// Folders searched for Mac programs Winetricks calls. Apps started from
    /// the Finder get a short PATH without Homebrew, so its folders are
    /// added.
    public static func searchPath(base: String?) -> [String] {
        var folders = (base ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty }
        for folder in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        where !folders.contains(folder) {
            folders.append(folder)
        }
        return folders
    }

    /// The tools from `required` that are in none of `searchPath`.
    public static func missingTools(
        _ required: [String],
        searchPath: [String],
        fileManager: FileManager = .default
    ) -> [String] {
        required.filter { tool in
            !searchPath.contains { fileManager.isExecutableFile(atPath: ($0 as NSString).appendingPathComponent(tool)) }
        }
    }

    /// What Winetricks needs on top of the bottle's Wine environment: which
    /// `wine` and `wineserver` to use (the bottle's tree), where to cache
    /// downloads, and a PATH that finds Homebrew's tools.
    public static func environment(
        installation: WineInstallation,
        cache: URL,
        searchPath: [String]
    ) -> [String: String] {
        [
            "WINE": installation.wine.path,
            "WINESERVER": installation.wineserver.path,
            "W_CACHE": cache.path,
            "PATH": ([installation.binDirectory.path] + searchPath).joined(separator: ":"),
        ]
    }

    /// Downloads the script once (checking its checksum) and returns it.
    public static func installScript(
        _ config: RuntimeConfig.Winetricks,
        paths: AppPaths,
        log: LogFile,
        fileManager: FileManager = .default
    ) async throws -> URL {
        let script = paths.winetricksScript(version: config.version)
        if fileManager.isExecutableFile(atPath: script.path) {
            if let expected = config.sha256,
               (try? ArchiveInstaller.sha256(of: script))?.caseInsensitiveCompare(expected) != .orderedSame {
                try? fileManager.removeItem(at: script)
            } else {
                return script
            }
        }
        try fileManager.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = script.appendingPathExtension("partial")
        try? fileManager.removeItem(at: partial)
        log.append("\nLade Winetricks \(config.version) von \(config.url.absoluteString)\n")
        try await FileDownloader(destination: partial) { _ in }.download(from: config.url)
        if let expected = config.sha256 {
            let actual = try ArchiveInstaller.sha256(of: partial)
            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                try? fileManager.removeItem(at: partial)
                throw WineInstallError.checksumMismatch(name: "Winetricks", expected: expected, actual: actual)
            }
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: partial.path)
        try? fileManager.removeItem(at: script)
        try fileManager.moveItem(at: partial, to: script)
        return script
    }
}
