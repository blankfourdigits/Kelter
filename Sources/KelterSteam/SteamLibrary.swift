import Foundation
import KelterCore

/// A game (or tool) Steam has installed, read from `appmanifest_<id>.acf`.
public struct SteamApp: Equatable, Identifiable, Sendable {
    public var appID: Int
    public var name: String
    /// Folder name below `steamapps/common`.
    public var installDirectory: String
    /// The Steam library folder (the one containing `steamapps`) on the Mac.
    public var library: URL
    public var sizeOnDisk: Int64
    /// Steam's state bits; 4 means fully installed.
    public var stateFlags: Int
    public var lastPlayed: Date?

    public var id: Int { appID }

    /// Whether Steam considers the app ready to play (not still
    /// downloading or updating).
    public var isFullyInstalled: Bool {
        stateFlags & 4 != 0
    }

    /// `<library>/steamapps/common/<installDirectory>`.
    public var installURL: URL {
        library
            .appendingPathComponent("steamapps", isDirectory: true)
            .appendingPathComponent("common", isDirectory: true)
            .appendingPathComponent(installDirectory, isDirectory: true)
    }

    public init(
        appID: Int,
        name: String,
        installDirectory: String,
        library: URL,
        sizeOnDisk: Int64,
        stateFlags: Int,
        lastPlayed: Date?
    ) {
        self.appID = appID
        self.name = name
        self.installDirectory = installDirectory
        self.library = library
        self.sizeOnDisk = sizeOnDisk
        self.stateFlags = stateFlags
        self.lastPlayed = lastPlayed
    }
}

/// Reads which apps the Windows Steam client in a bottle has installed:
/// `steamapps/libraryfolders.vdf` names the library folders (also on other
/// drives), each folder's `steamapps/appmanifest_*.acf` describes one app.
public enum SteamLibrary {
    /// Parses one `appmanifest_*.acf`. Returns `nil` if the file does not
    /// describe an app (no id, name or install folder).
    public static func app(fromManifest manifest: VDFValue, library: URL) -> SteamApp? {
        guard let state = manifest["AppState"],
              let appID = state["appid"]?.string.flatMap({ Int($0) }),
              let name = state["name"]?.string, !name.isEmpty,
              let installDirectory = state["installdir"]?.string, !installDirectory.isEmpty
        else { return nil }
        let lastPlayed = state["LastPlayed"]?.string.flatMap { TimeInterval($0) }
            .flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        return SteamApp(
            appID: appID,
            name: name,
            installDirectory: installDirectory,
            library: library,
            sizeOnDisk: state["SizeOnDisk"]?.string.flatMap { Int64($0) } ?? 0,
            stateFlags: state["StateFlags"]?.string.flatMap { Int($0) } ?? 0,
            lastPlayed: lastPlayed
        )
    }

    /// The Windows paths of the library folders in `libraryfolders.vdf`,
    /// in file order. Handles the current format (`"0" { "path" "…" }`) and
    /// the old one (`"1" "D:\\Games"`).
    public static func libraryFolderPaths(from file: VDFValue) -> [String] {
        let root = file["libraryfolders"] ?? file["LibraryFolders"] ?? .object([])
        return root.entries.compactMap { entry in
            guard Int(entry.key) != nil else { return nil }   // skips "contentstatsid" and the like
            if let path = entry.value.string { return path }
            return entry.value["path"]?.string
        }
    }

    /// Turns a Windows path such as `D:\Games\Steam` into a path on the Mac,
    /// through the bottle's drive links (`<prefix>/dosdevices/d:`).
    /// Returns `nil` for paths without a drive letter or for unknown drives.
    public static func unixURL(
        forWindowsPath path: String,
        prefix: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let parts = path.split(separator: "\\", omittingEmptySubsequences: true).map(String.init)
        guard let drive = parts.first, drive.count == 2, drive.hasSuffix(":"),
              drive.first?.isLetter == true
        else { return nil }
        let link = prefix
            .appendingPathComponent("dosdevices", isDirectory: true)
            .appendingPathComponent(drive.lowercased(), isDirectory: true)
        guard fileManager.fileExists(atPath: link.path) else { return nil }
        var url = link.resolvingSymlinksInPath()
        for component in parts.dropFirst() where component != "." {
            guard component != ".." else { return nil }
            url.appendPathComponent(component)
        }
        return url
    }

    /// All installed apps of the Steam client in `steamDirectory` (the
    /// folder with `steam.exe`), sorted by name. Unreadable manifests are
    /// skipped; an app found in two folders is listed once.
    public static func scan(
        steamDirectory: URL,
        prefix: URL,
        fileManager: FileManager = .default
    ) -> [SteamApp] {
        var libraries = [steamDirectory.standardizedFileURL]
        let foldersFile = steamDirectory
            .appendingPathComponent("steamapps", isDirectory: true)
            .appendingPathComponent("libraryfolders.vdf")
        if let file = try? VDF.parse(contentsOf: foldersFile) {
            for path in libraryFolderPaths(from: file) {
                guard let url = unixURL(forWindowsPath: path, prefix: prefix, fileManager: fileManager)?
                    .standardizedFileURL
                else { continue }
                if !libraries.contains(where: { $0.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }) {
                    libraries.append(url)
                }
            }
        }

        var apps: [Int: SteamApp] = [:]
        for library in libraries {
            let steamapps = library.appendingPathComponent("steamapps", isDirectory: true)
            guard let names = try? fileManager.contentsOfDirectory(atPath: steamapps.path) else { continue }
            for name in names.sorted()
            where name.lowercased().hasPrefix("appmanifest_") && name.lowercased().hasSuffix(".acf") {
                guard let manifest = try? VDF.parse(contentsOf: steamapps.appendingPathComponent(name)),
                      let app = app(fromManifest: manifest, library: library),
                      apps[app.appID] == nil
                else { continue }
                apps[app.appID] = app
            }
        }
        return apps.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.appID < $1.appID : order == .orderedAscending
        }
    }

    // MARK: Covers and starting

    /// Picture names in Steam's cache, best fitting for a cover first.
    static let coverNames = ["library_600x900.jpg", "library_capsule.jpg", "library_header.jpg", "header.jpg"]

    /// A cover picture Steam has already cached for the app, if any:
    /// `appcache/librarycache/<id>/` holds the pictures directly or in
    /// subfolders named after their hash.
    public static func coverImage(
        appID: Int,
        steamDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let folder = steamDirectory
            .appendingPathComponent("appcache", isDirectory: true)
            .appendingPathComponent("librarycache", isDirectory: true)
            .appendingPathComponent(String(appID), isDirectory: true)
        let subfolders = ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [])
            .sorted()
            .map { folder.appendingPathComponent($0, isDirectory: true) }
            .filter { url in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
        for name in coverNames {
            for candidate in [folder] + subfolders {
                let file = candidate.appendingPathComponent(name)
                if fileManager.fileExists(atPath: file.path) { return file }
            }
        }
        return nil
    }

    /// The apps worth showing as games: without the hidden ones.
    public static func games(_ apps: [SteamApp], hiding hiddenAppIDs: [Int]?) -> [SteamApp] {
        let hidden = Set(hiddenAppIDs ?? [])
        return apps.filter { !hidden.contains($0.appID) }
    }

    /// The argument that makes `steam.exe` start a game, in a running
    /// Steam as well as in a new one.
    public static func runGameArgument(appID: Int) -> String {
        "steam://rungameid/\(appID)"
    }
}
