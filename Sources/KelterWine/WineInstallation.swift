import Foundation
import KelterCore

/// An unpacked Wine build on disk.
public struct WineInstallation: Equatable, Sendable {
    /// The unpacked archive root, e.g. `…/Runtimes/wine/11.21/Wine Staging.app`.
    public let root: URL
    public let binDirectory: URL
    public let libDirectory: URL
    public let version: String

    public init(root: URL, binDirectory: URL, libDirectory: URL, version: String) {
        self.root = root
        self.binDirectory = binDirectory
        self.libDirectory = libDirectory
        self.version = version
    }

    /// The Wine loader. Tools such as `winecfg` or `wineboot` are started
    /// through it (`wine winecfg`), which works with every build layout.
    public var wine: URL {
        binDirectory.appendingPathComponent("wine")
    }

    public var wineserver: URL {
        binDirectory.appendingPathComponent("wineserver")
    }

    /// Where the configured Wine version would be, whether or not it exists.
    public static func expected(paths: AppPaths, config: RuntimeConfig.Wine) -> WineInstallation {
        let root = paths.wineDirectory(version: config.version)
            .appendingPathComponent(config.archiveRoot, isDirectory: true)
        return WineInstallation(
            root: root,
            binDirectory: root.appendingPathComponent(config.binDirectory, isDirectory: true),
            libDirectory: root.appendingPathComponent(config.libDirectory, isDirectory: true),
            version: config.version
        )
    }

    /// The configured Wine version if it is installed, otherwise `nil`.
    public static func locate(
        paths: AppPaths,
        config: RuntimeConfig.Wine,
        fileManager: FileManager = .default
    ) -> WineInstallation? {
        let candidate = expected(paths: paths, config: config)
        guard fileManager.isExecutableFile(atPath: candidate.wine.path),
              fileManager.isExecutableFile(atPath: candidate.wineserver.path)
        else { return nil }
        return candidate
    }
}
