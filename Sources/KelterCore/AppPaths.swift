import Foundation

/// All locations Kelter reads from or writes to.
///
/// Everything lives below one root so that tests can point the whole app at a
/// temporary directory.
public struct AppPaths: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Kelter`
    public static func standard(fileManager: FileManager = .default) -> AppPaths {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        return AppPaths(root: base.appendingPathComponent("Kelter", isDirectory: true))
    }

    public var bottlesDirectory: URL {
        root.appendingPathComponent("Bottles", isDirectory: true)
    }

    public var runtimesDirectory: URL {
        root.appendingPathComponent("Runtimes", isDirectory: true)
    }

    public var downloadsDirectory: URL {
        root.appendingPathComponent("Downloads", isDirectory: true)
    }

    public var logsDirectory: URL {
        root.appendingPathComponent("Logs", isDirectory: true)
    }

    public var logFile: URL {
        logsDirectory.appendingPathComponent("kelter.log")
    }

    /// Optional user override of the bundled `runtimes.json`.
    public var userRuntimeConfig: URL {
        root.appendingPathComponent("runtimes.json")
    }

    /// Directory one Wine version is unpacked into.
    public func wineDirectory(version: String) -> URL {
        runtimesDirectory
            .appendingPathComponent("wine", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    /// A copy of Wine with a graphics layer put into it.
    public func wineVariantDirectory(name: String) -> URL {
        runtimesDirectory
            .appendingPathComponent("wine-variants", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    /// Directory one version of a graphics layer is unpacked into.
    public func graphicsLayerDirectory(id: String, version: String) -> URL {
        runtimesDirectory
            .appendingPathComponent("graphics", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    /// Directory one version of the support package is unpacked into.
    public func supportDirectory(version: String) -> URL {
        runtimesDirectory
            .appendingPathComponent("support", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    public func ensureDirectories(fileManager: FileManager = .default) throws {
        for directory in [root, bottlesDirectory, runtimesDirectory, downloadsDirectory, logsDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
