import Foundation

/// Contents of `runtimes.json`: which builds Kelter downloads and where they
/// come from. Nothing about versions or URLs is compiled into the app.
public struct RuntimeConfig: Codable, Equatable, Sendable {
    public struct Wine: Codable, Equatable, Sendable {
        /// Human readable name shown in the UI.
        public var name: String
        public var version: String
        /// Download URL of the `.tar.xz` archive.
        public var url: URL
        /// Expected SHA-256 of the archive (hex). `nil` skips verification.
        public var sha256: String?
        /// Top level directory inside the archive, e.g. `Wine Staging.app`.
        public var archiveRoot: String
        /// Directory with `wine` and `wineserver`, relative to `archiveRoot`.
        public var binDirectory: String
        /// Wine's `lib` directory, relative to `archiveRoot`.
        public var libDirectory: String
        /// Whether this build understands `WINEESYNC`.
        public var supportsESync: Bool
        /// Whether this build understands `WINEMSYNC`.
        public var supportsMSync: Bool

        public init(
            name: String,
            version: String,
            url: URL,
            sha256: String?,
            archiveRoot: String,
            binDirectory: String,
            libDirectory: String,
            supportsESync: Bool,
            supportsMSync: Bool
        ) {
            self.name = name
            self.version = version
            self.url = url
            self.sha256 = sha256
            self.archiveRoot = archiveRoot
            self.binDirectory = binDirectory
            self.libDirectory = libDirectory
            self.supportsESync = supportsESync
            self.supportsMSync = supportsMSync
        }
    }

    /// A second download that belongs to the Wine build: the libraries Wine
    /// loads at run time and the Direct3D renderers. Optional, because some
    /// Wine builds bring everything themselves.
    public struct Support: Codable, Equatable, Sendable {
        public struct Renderer: Codable, Equatable, Sendable {
            /// Kelter's name for it: `d9vk`, `dxmt`, `dxvk` or `d3dmetal`.
            public var id: String
            /// The environment variable through which the Wine build is told
            /// where this renderer lives.
            public var variable: String
            /// Folder with `x86_64-windows` etc., relative to `archiveRoot`.
            public var path: String

            public init(id: String, variable: String, path: String) {
                self.id = id
                self.variable = variable
                self.path = path
            }
        }

        public var name: String
        public var version: String
        public var url: URL
        public var sha256: String?
        /// Top level directory inside the archive.
        public var archiveRoot: String
        /// Folders with run-time libraries, relative to `archiveRoot`.
        public var libraryPaths: [String]
        public var gstreamerPluginPath: String?
        /// Vulkan driver description (ICD json), relative to `archiveRoot`.
        public var vulkanDriverFile: String?
        public var renderers: [Renderer]
        /// Paths relative to `archiveRoot` that are deleted after unpacking.
        /// Used for Apple's D3DMetal, which Kelter only takes from a Game
        /// Porting Toolkit the user downloaded from Apple.
        public var removeAfterInstall: [String]
        /// Extra environment variables for every Wine process.
        public var environment: [String: String]

        public init(
            name: String,
            version: String,
            url: URL,
            sha256: String?,
            archiveRoot: String,
            libraryPaths: [String],
            gstreamerPluginPath: String?,
            vulkanDriverFile: String?,
            renderers: [Renderer],
            removeAfterInstall: [String],
            environment: [String: String]
        ) {
            self.name = name
            self.version = version
            self.url = url
            self.sha256 = sha256
            self.archiveRoot = archiveRoot
            self.libraryPaths = libraryPaths
            self.gstreamerPluginPath = gstreamerPluginPath
            self.vulkanDriverFile = vulkanDriverFile
            self.renderers = renderers
            self.removeAfterInstall = removeAfterInstall
            self.environment = environment
        }
    }

    public struct Steam: Codable, Equatable, Sendable {
        /// A named set of start parameters offered in the UI.
        public struct ArgumentPreset: Codable, Equatable, Sendable {
            public var name: String
            public var arguments: [String]

            public init(name: String, arguments: [String]) {
                self.name = name
                self.arguments = arguments
            }
        }

        /// Makes Steam's window visible under Wine on macOS.
        ///
        /// Steam draws its window with an embedded Chromium. Chromium paints
        /// from a second process, which Wine's Mac driver cannot display, and
        /// Steam offers no start parameter that changes this. A small helper
        /// library, loaded only into Steam's browser process, adds the
        /// Chromium switches listed here.
        public struct UIFix: Codable, Equatable, Sendable {
            public var enabled: Bool
            /// The helper library, relative to Kelter's resources folder.
            public var library: String
            /// Wine's own winmm.dll, relative to Wine's `lib` directory.
            public var builtinLibrary: String
            /// Chromium switches added to Steam's browser process.
            public var browserArguments: [String]

            public init(enabled: Bool, library: String, builtinLibrary: String, browserArguments: [String]) {
                self.enabled = enabled
                self.library = library
                self.builtinLibrary = builtinLibrary
                self.browserArguments = browserArguments
            }
        }

        /// Where Valve's Windows installer is downloaded from.
        public var installerURL: URL
        /// Arguments for an unattended install, e.g. `/S`.
        public var installerArguments: [String]
        /// `steam.exe` relative to the bottle's `drive_c`.
        public var executablePath: String
        /// Start parameters used when a bottle has none of its own. The Steam
        /// client needs workarounds under Wine, and which ones changes with
        /// client updates, so they live here and not in the code.
        public var defaultArguments: [String]
        public var argumentPresets: [ArgumentPreset]
        public var uiFix: UIFix
        /// DLL overrides for Steam and everything it starts, e.g. switching
        /// off the Steam overlay library, which stops games from starting
        /// under Wine on macOS. A bottle's own overrides win.
        public var dllOverrides: [String: String]?

        public init(
            installerURL: URL,
            installerArguments: [String],
            executablePath: String,
            defaultArguments: [String],
            argumentPresets: [ArgumentPreset],
            uiFix: UIFix,
            dllOverrides: [String: String]? = nil
        ) {
            self.installerURL = installerURL
            self.installerArguments = installerArguments
            self.executablePath = executablePath
            self.defaultArguments = defaultArguments
            self.argumentPresets = argumentPresets
            self.uiFix = uiFix
            self.dllOverrides = dllOverrides
        }
    }

    public var schemaVersion: Int
    public var wine: Wine
    /// Kelter's own changes to Wine (Tools/wine-patches), which some
    /// graphics layers need, for example Wine's macOS driver with the
    /// functions DXMT and D3DMetal look up. They are built on the Mac by a
    /// script from the repository (no foreign binaries are shipped) into
    /// `Runtimes/wine-files/<wineVersion>-<version>/`.
    public struct WinePatches: Codable, Equatable, Sendable {
        /// Shown in messages.
        public var name: String
        /// Revision of the changes; a new one builds new copies of Wine.
        public var version: String
        /// The Wine version the files are built for.
        public var wineVersion: String
        /// The script that builds the files, relative to the project folder.
        public var buildScript: String

        public init(name: String, version: String, wineVersion: String, buildScript: String) {
            self.name = name
            self.version = version
            self.wineVersion = wineVersion
            self.buildScript = buildScript
        }
    }

    /// A disk image the user downloads from the layer's vendor and picks in
    /// Kelter, as an alternative to `url`.
    public struct DiskImage: Codable, Equatable, Sendable {
        /// Folder inside the mounted image that corresponds to `archiveRoot`.
        public var root: String
        /// Where the user gets the image.
        public var downloadPage: URL

        public init(root: String, downloadPage: URL) {
            self.root = root
            self.downloadPage = downloadPage
        }
    }

    /// Terms the user has to agree to before Kelter fetches a layer.
    public struct License: Codable, Equatable, Sendable {
        public var name: String
        public var url: URL
        /// Short plain-language summary shown next to the link.
        public var summary: String

        public init(name: String, url: URL, summary: String) {
            self.name = name
            self.url = url
            self.summary = summary
        }
    }

    /// A Direct3D translation layer that is put into a copy of the Wine
    /// build, replacing Wine's own libraries there.
    public struct GraphicsLayer: Codable, Equatable, Sendable {
        /// Matches a graphics choice of a bottle, e.g. `dxmt`.
        public var id: String
        public var name: String
        public var version: String
        public var url: URL
        public var sha256: String?
        /// Folder inside the archive that holds `x86_64-windows` and so on.
        public var archiveRoot: String
        /// Where those folders go, relative to Wine's `lib` directory
        /// (`.` for the `lib` directory itself).
        public var libraryTarget: String
        /// Libraries a bottle needs in its own Windows folders as well,
        /// because Wine only loads a built-in library that also exists
        /// there: folder below `archiveRoot` → folder inside the prefix.
        public var prefixLibraries: [String: String]?
        /// Files from `winePatches` the layer needs, relative to Wine's
        /// `lib/wine`, e.g. `x86_64-unix/winemac.so`.
        public var wineFiles: [String]?
        /// If set, only these paths below `archiveRoot` are kept, for
        /// packages that bring a whole Wine of their own.
        public var include: [String]?
        /// Another way to get the files: a disk image from the vendor.
        public var diskImage: DiskImage?
        /// Terms to agree to before the layer is fetched.
        public var license: License?
        /// If set, the layer cannot be chosen, and this says why (for
        /// example a known crash). Bottles that use it get the reason.
        public var paused: String?

        public init(
            id: String,
            name: String,
            version: String,
            url: URL,
            sha256: String?,
            archiveRoot: String,
            libraryTarget: String,
            prefixLibraries: [String: String]? = nil,
            wineFiles: [String]? = nil,
            include: [String]? = nil,
            diskImage: DiskImage? = nil,
            license: License? = nil,
            paused: String? = nil
        ) {
            self.id = id
            self.name = name
            self.version = version
            self.url = url
            self.sha256 = sha256
            self.archiveRoot = archiveRoot
            self.libraryTarget = libraryTarget
            self.prefixLibraries = prefixLibraries
            self.wineFiles = wineFiles
            self.include = include
            self.diskImage = diskImage
            self.license = license
            self.paused = paused
        }
    }

    public var support: Support?
    public var winePatches: WinePatches?
    public var graphicsLayers: [GraphicsLayer]?
    public var steam: Steam

    public init(
        schemaVersion: Int,
        wine: Wine,
        support: Support? = nil,
        winePatches: WinePatches? = nil,
        graphicsLayers: [GraphicsLayer]? = nil,
        steam: Steam
    ) {
        self.schemaVersion = schemaVersion
        self.wine = wine
        self.support = support
        self.winePatches = winePatches
        self.graphicsLayers = graphicsLayers
        self.steam = steam
    }

    public func graphicsLayer(for backend: GraphicsBackendKind) -> GraphicsLayer? {
        graphicsLayers?.first { $0.id == backend.rawValue }
    }

    /// Why a graphics choice cannot be used right now, or `nil` if it can.
    public func pauseReason(for backend: GraphicsBackendKind) -> String? {
        graphicsLayer(for: backend)?.paused
    }
}

public enum RuntimeConfigError: LocalizedError, Equatable {
    case notFound([String])
    case invalid(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let paths):
            return "Keine runtimes.json gefunden. Gesucht in:\n" + paths.joined(separator: "\n")
        case .invalid(let path, let reason):
            return "Die Konfiguration \(path) ist fehlerhaft: \(reason)"
        }
    }
}

extension RuntimeConfig {
    public static func load(from url: URL) throws -> RuntimeConfig {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(RuntimeConfig.self, from: data)
        } catch {
            throw RuntimeConfigError.invalid(path: url.path, reason: String(describing: error))
        }
    }

    /// Loads the first candidate that exists. A candidate that exists but is
    /// broken is an error; it is not silently skipped, so a typo in a user
    /// override does not fall back to the bundled defaults unnoticed.
    public static func loadFirst(
        candidates: [URL],
        fileManager: FileManager = .default
    ) throws -> (config: RuntimeConfig, source: URL) {
        for url in candidates where fileManager.fileExists(atPath: url.path) {
            return (try load(from: url), url)
        }
        throw RuntimeConfigError.notFound(candidates.map(\.path))
    }
}
