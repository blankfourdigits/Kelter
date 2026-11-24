import Foundation
import KelterCore

/// What uninstalling one game removes. Built by `SteamUninstall.plan`.
public struct SteamUninstallPlan: Equatable, Sendable {
    public var appID: Int
    /// The game's files and Steam's own data for it; always removed.
    public var gameItems: [URL]
    /// Local save folders Kelter could identify; removed only on request.
    public var saveFolders: [URL]

    public init(appID: Int, gameItems: [URL], saveFolders: [URL]) {
        self.appID = appID
        self.gameItems = gameItems
        self.saveFolders = saveFolders
    }
}

public enum SteamUninstallError: LocalizedError, Equatable {
    /// The install folder name from the manifest would leave `steamapps/common`.
    case unsafeInstallDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .unsafeInstallDirectory(let name):
            return loc("Der Installationsordner „%@“ aus Steams Manifest ist nicht zulässig. Kelter löscht nichts.", name)
        }
    }
}

/// Uninstalls a game without Steam: Steam itself runs the game's uninstall
/// script first, and some of those programs (32-bit .NET tools) hang under
/// Wine on macOS, which leaves Steam stuck at "Uninstalling".
public enum SteamUninstall {
    /// Windows folders an uninstall script may name, and where they are in
    /// the bottle: below the Windows user's folder or below `drive_c`.
    static let scriptFolders: [(variable: String, inUserFolder: Bool, path: [String])] = [
        ("APPDATA", true, ["AppData", "Roaming"]),
        ("LOCALAPPDATA", true, ["AppData", "Local"]),
        ("USERPROFILE", true, []),
        ("PROGRAMDATA", false, ["ProgramData"]),
        ("PUBLIC", false, ["users", "Public"]),
    ]

    /// A save folder from a script must lie at least this deep below the
    /// variable's folder; "%USERPROFILE%/Documents" alone is far too broad.
    static let minimumSaveDepth = 2

    /// Everything that belongs to `app`, existing items only.
    public static func plan(
        for app: SteamApp,
        steamDirectory: URL,
        prefix: URL,
        fileManager: FileManager = .default
    ) throws -> SteamUninstallPlan {
        let name = app.installDirectory
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\")
        else { throw SteamUninstallError.unsafeInstallDirectory(name) }

        let id = String(app.appID)
        let steamapps = app.library.appendingPathComponent("steamapps", isDirectory: true)
        let candidates = [
            app.installURL,
            steamapps.appendingPathComponent("appmanifest_\(id).acf"),
            steamapps.appendingPathComponent("downloading/\(id)", isDirectory: true),
            steamapps.appendingPathComponent("temp/\(id)", isDirectory: true),
            steamapps.appendingPathComponent("shadercache/\(id)", isDirectory: true),
            steamapps.appendingPathComponent("workshop/appworkshop_\(id).acf"),
            steamapps.appendingPathComponent("workshop/content/\(id)", isDirectory: true),
            steamapps.appendingPathComponent("workshop/downloads/\(id)", isDirectory: true),
        ]
        let gameItems = candidates.filter { exists($0, fileManager) }

        var saves: [URL] = []
        // Steam's local copy of the app's cloud saves, per Steam account.
        let userdata = steamDirectory.appendingPathComponent("userdata", isDirectory: true)
        for account in ((try? fileManager.contentsOfDirectory(atPath: userdata.path)) ?? []).sorted()
        where Int(account) != nil {
            let folder = userdata.appendingPathComponent(account, isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
            if isDirectory(folder, fileManager) { saves.append(folder) }
        }
        // Folders the game's own uninstall script would clean up.
        if let script = installScript(in: app.installURL, fileManager: fileManager) {
            for path in uninstallPaths(in: script) {
                // Wine may link user folders such as Documents to the Mac's
                // own; show and delete the real place.
                if let folder = resolve(path, prefix: prefix, fileManager: fileManager)?
                    .resolvingSymlinksInPath(),
                   isDirectory(folder, fileManager), !saves.contains(folder) {
                    saves.append(folder)
                }
            }
        }
        return SteamUninstallPlan(appID: app.appID, gameItems: gameItems, saveFolders: saves)
    }

    /// Deletes the items for good. Missing ones are skipped.
    public static func remove(_ items: [URL], fileManager: FileManager = .default) throws {
        for item in items where (try? fileManager.attributesOfItem(atPath: item.path)) != nil {
            try fileManager.removeItem(at: item)
        }
    }

    // MARK: Uninstall scripts

    /// The game's install script (`installscript.vdf` or `install.vdf`).
    static func installScript(in installURL: URL, fileManager: FileManager) -> VDFValue? {
        let names = (try? fileManager.contentsOfDirectory(atPath: installURL.path)) ?? []
        for wanted in ["installscript.vdf", "install.vdf"] {
            if let name = names.first(where: { $0.lowercased() == wanted }),
               let script = try? VDF.parse(contentsOf: installURL.appendingPathComponent(name)) {
                return script
            }
        }
        return nil
    }

    /// Windows paths that start with a known folder variable, from the
    /// commands under "Run Process On Uninstall".
    static func uninstallPaths(in script: VDFValue) -> [String] {
        guard let root = script["InstallScript"] ?? script["installscript"] else { return [] }
        let section = root.entries.first { $0.key.lowercased() == "run process on uninstall" }?.value
        guard let processes = section?.entries else { return [] }
        var paths: [String] = []
        for process in processes {
            for entry in process.value.entries where entry.key.lowercased().hasPrefix("command") {
                guard let command = entry.value.string else { continue }
                for path in folderPaths(in: command) where !paths.contains(path) {
                    paths.append(path)
                }
            }
        }
        return paths
    }

    /// Pieces of a command line such as `-path "%APPDATA%/SEGA/P5R/"` that
    /// begin with `%VARIABLE%`: quoted ones whole, others up to a space.
    static func folderPaths(in command: String) -> [String] {
        var results: [String] = []
        var rest = Substring(command)
        while let start = rest.firstIndex(of: "%") {
            let quoted = start > rest.startIndex && rest[rest.index(before: start)] == "\""
            let end = quoted
                ? rest[start...].firstIndex(of: "\"") ?? rest.endIndex
                : rest[start...].firstIndex(where: { $0 == " " || $0 == "\"" }) ?? rest.endIndex
            let piece = String(rest[start..<end])
            if scriptFolders.contains(where: { piece.uppercased().hasPrefix("%\($0.variable)%") }) {
                results.append(piece)
            }
            rest = end < rest.endIndex ? rest[rest.index(after: end)...] : ""
        }
        return results
    }

    /// The folder in the bottle for `%VARIABLE%\a\b`, or `nil` if the
    /// variable is unknown, the path is too shallow or leaves its folder.
    static func resolve(_ path: String, prefix: URL, fileManager: FileManager) -> URL? {
        guard let folder = scriptFolders.first(where: { path.uppercased().hasPrefix("%\($0.variable)%") })
        else { return nil }
        let tail = path.dropFirst(folder.variable.count + 2)
        let parts = tail.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
        guard parts.count >= minimumSaveDepth, !parts.contains(".."), !parts.contains(".") else { return nil }

        let driveC = prefix.appendingPathComponent("drive_c", isDirectory: true)
        var url = driveC
        if folder.inUserFolder {
            guard let user = windowsUserFolder(driveC: driveC, fileManager: fileManager) else { return nil }
            url = user
        }
        for component in folder.path + parts {
            url.appendPathComponent(component, isDirectory: true)
        }
        return url
    }

    /// `drive_c/users/<name>`: the one user folder besides `Public`.
    static func windowsUserFolder(driveC: URL, fileManager: FileManager) -> URL? {
        let users = driveC.appendingPathComponent("users", isDirectory: true)
        let names = ((try? fileManager.contentsOfDirectory(atPath: users.path)) ?? [])
            .filter { $0 != "Public" && !$0.hasPrefix(".") }
            .filter { isDirectory(users.appendingPathComponent($0), fileManager) }
        guard names.count == 1 else { return nil }
        return users.appendingPathComponent(names[0], isDirectory: true)
    }

    // MARK: Helpers

    private static func exists(_ url: URL, _ fileManager: FileManager) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    private static func isDirectory(_ url: URL, _ fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
