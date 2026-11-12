import Foundation
import KelterCore

/// A copy of the Wine installation with one graphics layer (for example
/// DXMT) put in place of Wine's own Direct3D libraries.
///
/// Wine looks for its built-in libraries in its own folder first, so a layer
/// that replaces `d3d11.dll` has to live inside a Wine tree. Instead of
/// changing the one Wine every bottle uses, Kelter keeps a second tree per
/// layer and starts a bottle with the tree that matches its graphics choice.
/// On APFS the copy is a clone and takes almost no extra space.
public final class WineVariantInstaller: @unchecked Sendable {
    static let markerFileName = ".kelter-variant-complete"

    private let paths: AppPaths
    private let wine: RuntimeConfig.Wine
    private let layer: RuntimeConfig.GraphicsLayer
    private let log: LogFile
    private let fileManager = FileManager.default

    public init(paths: AppPaths, wine: RuntimeConfig.Wine, layer: RuntimeConfig.GraphicsLayer, log: LogFile) {
        self.paths = paths
        self.wine = wine
        self.layer = layer
        self.log = log
    }

    // MARK: Locations

    static func variantDirectory(paths: AppPaths, wine: RuntimeConfig.Wine, layer: RuntimeConfig.GraphicsLayer) -> URL {
        paths.wineVariantDirectory(name: "\(wine.version)+\(layer.id)-\(layer.version)")
    }

    /// Where the variant would be, whether or not it exists.
    public static func expected(
        paths: AppPaths,
        wine: RuntimeConfig.Wine,
        layer: RuntimeConfig.GraphicsLayer
    ) -> WineInstallation {
        let root = variantDirectory(paths: paths, wine: wine, layer: layer)
            .appendingPathComponent(wine.archiveRoot, isDirectory: true)
        return WineInstallation(
            root: root,
            binDirectory: root.appendingPathComponent(wine.binDirectory, isDirectory: true),
            libDirectory: root.appendingPathComponent(wine.libDirectory, isDirectory: true),
            version: wine.version
        )
    }

    /// The variant if it was built completely, otherwise `nil`.
    public static func locate(
        paths: AppPaths,
        wine: RuntimeConfig.Wine,
        layer: RuntimeConfig.GraphicsLayer,
        fileManager: FileManager = .default
    ) -> WineInstallation? {
        let directory = variantDirectory(paths: paths, wine: wine, layer: layer)
        let candidate = expected(paths: paths, wine: wine, layer: layer)
        guard fileManager.fileExists(atPath: directory.appendingPathComponent(markerFileName).path),
              fileManager.isExecutableFile(atPath: candidate.wine.path)
        else { return nil }
        return candidate
    }

    // MARK: Installing

    /// Downloads the layer, copies `base` and puts the layer's files into
    /// the copy.
    public func install(
        base: WineInstallation,
        onPhase: @escaping @Sendable (WineInstallPhase) -> Void
    ) async throws -> WineInstallation {
        let libraryTarget = try ArchiveInstaller.safeRelativePath(layer.libraryTarget)
        let archiveRoot = try ArchiveInstaller.safeRelativePath(layer.archiveRoot)

        // 1. The layer itself.
        let layerDirectory = paths.graphicsLayerDirectory(id: layer.id, version: layer.version)
        let installer = ArchiveInstaller(paths: paths, log: log)
        try await installer.install(
            ArchivePackage(
                name: layer.name,
                version: layer.version,
                url: layer.url,
                sha256: layer.sha256,
                target: layerDirectory
            ),
            onPhase: onPhase
        )
        let layerFiles = layerDirectory.appendingPathComponent(archiveRoot, isDirectory: true)
        guard fileManager.fileExists(atPath: layerFiles.path) else {
            throw WineInstallError.binaryMissing(layerFiles.path)
        }

        // 2. A copy of Wine, built next to its final place and moved there
        //    only when complete.
        onPhase(.extracting)
        let directory = Self.variantDirectory(paths: paths, wine: wine, layer: layer)
        let staging = directory.deletingLastPathComponent()
            .appendingPathComponent(directory.lastPathComponent + ".partial", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let copy = staging.appendingPathComponent(wine.archiveRoot, isDirectory: true)
            try await cloneTree(from: base.root, to: copy)

            // 3. The layer's files over Wine's own.
            let target = copy
                .appendingPathComponent(wine.libDirectory, isDirectory: true)
                .appendingPathComponent(libraryTarget, isDirectory: true)
            let replaced = try Self.overlay(from: layerFiles, onto: target, fileManager: fileManager)
            log.append("\(layer.name) \(layer.version): \(replaced) Dateien in die Wine-Kopie gelegt.\n")

            try Data().write(to: staging.appendingPathComponent(Self.markerFileName))
            try? fileManager.removeItem(at: directory)
            try fileManager.moveItem(at: staging, to: directory)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }

        guard let installation = Self.locate(paths: paths, wine: wine, layer: layer) else {
            throw WineInstallError.binaryMissing(Self.expected(paths: paths, wine: wine, layer: layer).wine.path)
        }
        log.append("Wine mit \(layer.name) ist bereit: \(installation.root.path)\n")
        return installation
    }

    /// Copies a folder. `cp -c` asks APFS for clones, which share their data
    /// with the original until one of them changes; on other file systems
    /// the plain copy below is used.
    private func cloneTree(from source: URL, to destination: URL) async throws {
        let cloned = try await ProcessWaiter.runTool("/bin/cp", ["-Rc", source.path, destination.path], log: log)
        if cloned == 0 { return }
        try? fileManager.removeItem(at: destination)
        let copied = try await ProcessWaiter.runTool("/bin/cp", ["-R", source.path, destination.path], log: log)
        guard copied == 0 else { throw WineInstallError.extractionFailed(copied) }
    }

    /// Copies every file below `source` to the same relative path below
    /// `target`, replacing what is there. Returns the number of files.
    static func overlay(from source: URL, onto target: URL, fileManager: FileManager) throws -> Int {
        guard let enumerator = fileManager.enumerator(atPath: source.path) else { return 0 }
        var count = 0
        while let relative = enumerator.nextObject() as? String {
            let from = source.appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: from.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            if relative.split(separator: "/").last?.hasPrefix(".") == true { continue }
            let to = target.appendingPathComponent(relative)
            try fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fileManager.attributesOfItem(atPath: to.path)) != nil {
                try fileManager.removeItem(at: to)
            }
            try fileManager.copyItem(at: from, to: to)
            count += 1
        }
        return count
    }
}
