import Foundation
import KelterCore

/// The unpacked support package: runtime libraries Wine loads (FreeType,
/// GnuTLS, MoltenVK, GStreamer …) and the Direct3D renderers.
public struct SupportInstallation: Equatable, Sendable {
    /// The unpacked archive root, e.g. `…/Runtimes/support/1.0.15/Template-1.0.15.app`.
    public let root: URL
    public let config: RuntimeConfig.Support

    public init(root: URL, config: RuntimeConfig.Support) {
        self.root = root
        self.config = config
    }

    /// Folders Wine should search for the libraries it loads at run time.
    public var libraryDirectories: [URL] {
        config.libraryPaths.map { root.appendingPathComponent($0, isDirectory: true) }
    }

    public var gstreamerPluginDirectory: URL? {
        config.gstreamerPluginPath.map { root.appendingPathComponent($0, isDirectory: true) }
    }

    /// The Vulkan driver description (ICD file) for MoltenVK.
    public var vulkanDriverFile: URL? {
        config.vulkanDriverFile.map { root.appendingPathComponent($0) }
    }

    /// The environment variable and folder for one renderer, if the package
    /// has it.
    public func renderer(id: String) -> (variable: String, directory: URL)? {
        guard let renderer = config.renderers.first(where: { $0.id == id }) else { return nil }
        return (renderer.variable, root.appendingPathComponent(renderer.path, isDirectory: true))
    }

    /// Where the configured package would be, whether or not it exists.
    public static func expected(paths: AppPaths, config: RuntimeConfig.Support) -> SupportInstallation {
        SupportInstallation(
            root: paths.supportDirectory(version: config.version)
                .appendingPathComponent(config.archiveRoot, isDirectory: true),
            config: config
        )
    }

    /// The configured package if it is installed, otherwise `nil`.
    public static func locate(
        paths: AppPaths,
        config: RuntimeConfig.Support,
        fileManager: FileManager = .default
    ) -> SupportInstallation? {
        let candidate = expected(paths: paths, config: config)
        guard fileManager.fileExists(atPath: candidate.root.path) else { return nil }
        for directory in candidate.libraryDirectories where !fileManager.fileExists(atPath: directory.path) {
            return nil
        }
        return candidate
    }
}
