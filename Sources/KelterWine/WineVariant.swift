import Foundation
import KelterCore

/// Problems with Kelter's changed Wine files that a graphics layer needs.
public enum WineFilesError: LocalizedError, Equatable {
    /// runtimes.json names files for a layer but no `winePatches`.
    case notConfigured(layer: String)
    /// The build script has not been run (or not for this revision).
    case missing(name: String, layer: String, files: [String], buildScript: String)
    /// The files are made for another Wine than the one in runtimes.json.
    case wrongWineVersion(name: String, expected: String, installed: String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let layer):
            return "\(layer) braucht angepasste Wine-Dateien, aber runtimes.json enthält keinen Abschnitt \"winePatches\"."
        case .missing(let name, let layer, let files, let buildScript):
            return """
                Für \(layer) fehlt noch: \(name) (\(files.joined(separator: ", "))).
                Diese Dateien werden auf deinem Mac gebaut. Im Terminal im Kelter-Ordner ausführen:

                bash \(buildScript)

                Danach \(layer) noch einmal auswählen.
                """
        case .wrongWineVersion(let name, let expected, let installed):
            return """
                \(name) ist für Wine \(expected) gedacht, eingestellt ist aber Wine \(installed). \
                Bitte runtimes.json anpassen und die Dateien für Wine \(installed) neu bauen.
                """
        }
    }
}

/// Problems with getting a graphics layer's own files.
public enum LayerSourceError: LocalizedError, Equatable {
    /// The layer offers no disk image.
    case noDiskImage(layer: String)
    /// hdiutil could not open the image (or it asks for a licence first).
    case cannotMount(name: String)
    /// A file the layer needs is not in the package.
    case fileMissing(layer: String, path: String)

    public var errorDescription: String? {
        switch self {
        case .noDiskImage(let layer):
            return "Für \(layer) ist kein Disk-Image vorgesehen."
        case .cannotMount(let name):
            return """
                \(name) konnte nicht geöffnet werden. Bitte die Datei im Finder per Doppelklick öffnen, \
                die Lizenz bestätigen und dann das geöffnete Laufwerk statt der Datei auswählen.
                """
        case .fileMissing(let layer, let path):
            return "Im ausgewählten Paket fehlt \(path). Ist das wirklich das Paket für \(layer)?"
        }
    }
}

/// Where a graphics layer's own files come from.
public enum LayerSource: Equatable, Sendable {
    /// The archive at the layer's `url`.
    case download
    /// A disk image (`.dmg`) or an already opened volume or folder.
    case diskImage(URL)
}

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

    private let patches: RuntimeConfig.WinePatches?

    public init(
        paths: AppPaths,
        wine: RuntimeConfig.Wine,
        layer: RuntimeConfig.GraphicsLayer,
        patches: RuntimeConfig.WinePatches?,
        log: LogFile
    ) {
        self.paths = paths
        self.wine = wine
        self.layer = layer
        self.patches = patches
        self.log = log
    }

    // MARK: Locations

    /// One folder per Wine version, layer version and revision of Kelter's
    /// Wine changes, so that a new revision builds a new copy.
    static func variantDirectory(
        paths: AppPaths,
        wine: RuntimeConfig.Wine,
        layer: RuntimeConfig.GraphicsLayer,
        patches: RuntimeConfig.WinePatches?
    ) -> URL {
        var name = "\(wine.version)+\(layer.id)-\(layer.version)"
        if let patches, layer.wineFiles?.isEmpty == false {
            name += "+wine-\(patches.version)"
        }
        return paths.wineVariantDirectory(name: name)
    }

    /// Where the variant would be, whether or not it exists.
    public static func expected(
        paths: AppPaths,
        wine: RuntimeConfig.Wine,
        layer: RuntimeConfig.GraphicsLayer,
        patches: RuntimeConfig.WinePatches?
    ) -> WineInstallation {
        let root = variantDirectory(paths: paths, wine: wine, layer: layer, patches: patches)
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
        patches: RuntimeConfig.WinePatches?,
        fileManager: FileManager = .default
    ) -> WineInstallation? {
        let directory = variantDirectory(paths: paths, wine: wine, layer: layer, patches: patches)
        let candidate = expected(paths: paths, wine: wine, layer: layer, patches: patches)
        guard fileManager.fileExists(atPath: directory.appendingPathComponent(markerFileName).path),
              fileManager.isExecutableFile(atPath: candidate.wine.path)
        else { return nil }
        return candidate
    }

    static let layerMarkerFileName = ".kelter-layer-complete"

    /// The folder that holds the layer's files as they go into Wine's `lib`
    /// (below `libraryTarget`). A layer with an `include` list keeps only
    /// those paths, directly in its folder.
    static func layerFilesDirectory(paths: AppPaths, layer: RuntimeConfig.GraphicsLayer) throws -> URL {
        let directory = paths.graphicsLayerDirectory(id: layer.id, version: layer.version)
        if layer.include != nil { return directory }
        return directory.appendingPathComponent(try ArchiveInstaller.safeRelativePath(layer.archiveRoot), isDirectory: true)
    }

    /// Whether the layer's own files were fetched completely before, so a
    /// new copy of Wine can be built without fetching them again.
    public static func hasLayerFiles(
        paths: AppPaths,
        layer: RuntimeConfig.GraphicsLayer,
        fileManager: FileManager = .default
    ) -> Bool {
        let directory = paths.graphicsLayerDirectory(id: layer.id, version: layer.version)
        return fileManager.fileExists(atPath: directory.appendingPathComponent(layerMarkerFileName).path)
    }

    // MARK: Installing

    /// Fetches the layer if needed (or from `source` if one is given),
    /// copies `base` and puts the layer's files into the copy.
    public func install(
        base: WineInstallation,
        source: LayerSource? = nil,
        onPhase: @escaping @Sendable (WineInstallPhase) -> Void
    ) async throws -> WineInstallation {
        let libraryTarget = layer.libraryTarget == "."
            ? nil : try ArchiveInstaller.safeRelativePath(layer.libraryTarget)
        // Fail before downloading anything if Kelter's Wine files are missing.
        try Self.checkWineFiles(layer: layer, patches: patches, wine: wine, paths: paths, fileManager: fileManager)

        // 1. The layer itself.
        if source != nil || !Self.hasLayerFiles(paths: paths, layer: layer, fileManager: fileManager) {
            try await fetchLayer(from: source ?? .download, onPhase: onPhase)
        }
        let layerFiles = try Self.layerFilesDirectory(paths: paths, layer: layer)
        guard fileManager.fileExists(atPath: layerFiles.path) else {
            throw WineInstallError.binaryMissing(layerFiles.path)
        }

        // 2. A copy of Wine, built next to its final place and moved there
        //    only when complete.
        onPhase(.extracting)
        let directory = Self.variantDirectory(paths: paths, wine: wine, layer: layer, patches: patches)
        let staging = directory.deletingLastPathComponent()
            .appendingPathComponent(directory.lastPathComponent + ".partial", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let copy = staging.appendingPathComponent(wine.archiveRoot, isDirectory: true)
            try await cloneTree(from: base.root, to: copy)

            // 3. The layer's files over Wine's own.
            var target = copy.appendingPathComponent(wine.libDirectory, isDirectory: true)
            if let libraryTarget {
                target = target.appendingPathComponent(libraryTarget, isDirectory: true)
            }
            let replaced = try Self.overlay(from: layerFiles, onto: target, fileManager: fileManager)
            log.append("\(layer.name) \(layer.version): \(replaced) Dateien in die Wine-Kopie gelegt.\n")

            // 4. Kelter's changed files of Wine itself, e.g. its macOS driver.
            if let patches, layer.wineFiles?.isEmpty == false {
                let wineLibraries = copy
                    .appendingPathComponent(wine.libDirectory, isDirectory: true)
                    .appendingPathComponent("wine", isDirectory: true)
                let count = try Self.installWineFiles(
                    layer: layer, patches: patches, wine: wine, paths: paths,
                    into: wineLibraries, fileManager: fileManager)
                log.append("\(patches.name) (Revision \(patches.version)): \(count) Dateien in die Wine-Kopie gelegt.\n")
            }

            try Data().write(to: staging.appendingPathComponent(Self.markerFileName))
            try? fileManager.removeItem(at: directory)
            try fileManager.moveItem(at: staging, to: directory)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }

        guard let installation = Self.locate(paths: paths, wine: wine, layer: layer, patches: patches) else {
            throw WineInstallError.binaryMissing(
                Self.expected(paths: paths, wine: wine, layer: layer, patches: patches).wine.path)
        }
        log.append("Wine mit \(layer.name) ist bereit: \(installation.root.path)\n")
        return installation
    }

    /// Gets the layer's files into its folder and marks them complete.
    private func fetchLayer(from source: LayerSource, onPhase: @escaping @Sendable (WineInstallPhase) -> Void) async throws {
        let layerDirectory = paths.graphicsLayerDirectory(id: layer.id, version: layer.version)
        try? fileManager.removeItem(at: layerDirectory.appendingPathComponent(Self.layerMarkerFileName))
        switch source {
        case .download:
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
            if let include = layer.include {
                // Keep only what the layer needs from a package that brings
                // a whole Wine of its own.
                let root = layerDirectory.appendingPathComponent(
                    try ArchiveInstaller.safeRelativePath(layer.archiveRoot), isDirectory: true)
                try replaceLayerDirectory(layerDirectory, withSelection: include, from: root)
            }
        case .diskImage(let image):
            guard let diskImage = layer.diskImage else { throw LayerSourceError.noDiskImage(layer: layer.name) }
            onPhase(.extracting)
            try await withMountedVolume(image) { volume in
                let root = volume.appendingPathComponent(
                    try ArchiveInstaller.safeRelativePath(diskImage.root), isDirectory: true)
                if let include = layer.include {
                    try replaceLayerDirectory(layerDirectory, withSelection: include, from: root)
                } else {
                    let selection = layerDirectory.deletingLastPathComponent()
                        .appendingPathComponent(layerDirectory.lastPathComponent + ".partial", isDirectory: true)
                    try? fileManager.removeItem(at: selection)
                    let target = selection.appendingPathComponent(
                        try ArchiveInstaller.safeRelativePath(layer.archiveRoot), isDirectory: true)
                    try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: root, to: target)
                    try? fileManager.removeItem(at: layerDirectory)
                    try fileManager.moveItem(at: selection, to: layerDirectory)
                }
            }
            _ = try? await ProcessWaiter.runTool(
                "/usr/bin/xattr", ["-dr", "com.apple.quarantine", layerDirectory.path], log: log)
            log.append("\(layer.name) aus \(image.lastPathComponent) übernommen.\n")
        }
        try Data().write(to: layerDirectory.appendingPathComponent(Self.layerMarkerFileName))
    }

    /// Replaces `layerDirectory` with only the `include` paths found below `root`.
    private func replaceLayerDirectory(_ layerDirectory: URL, withSelection include: [String], from root: URL) throws {
        let selection = layerDirectory.deletingLastPathComponent()
            .appendingPathComponent(layerDirectory.lastPathComponent + ".selection", isDirectory: true)
        try? fileManager.removeItem(at: selection)
        do {
            try Self.copySelection(include, from: root, to: selection, layerName: layer.name, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: selection)
            throw error
        }
        try? fileManager.removeItem(at: layerDirectory)
        try fileManager.moveItem(at: selection, to: layerDirectory)
    }

    /// Copies the `include` paths (files, folders or symbolic links) from
    /// `root` to the same places below `target`. Links stay links.
    static func copySelection(
        _ include: [String],
        from root: URL,
        to target: URL,
        layerName: String,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        for path in include {
            let relative = try ArchiveInstaller.safeRelativePath(path)
            let source = root.appendingPathComponent(relative)
            // attributesOfItem does not follow symbolic links.
            guard (try? fileManager.attributesOfItem(atPath: source.path)) != nil else {
                throw LayerSourceError.fileMissing(layer: layerName, path: relative)
            }
            let destination = target.appendingPathComponent(relative)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    /// Runs `body` with the opened volume: a `.dmg` is mounted read-only
    /// (without accepting any licence on the user's behalf) and detached
    /// afterwards; a folder is used as it is.
    private func withMountedVolume(_ image: URL, _ body: (URL) throws -> Void) async throws {
        guard image.pathExtension.lowercased() == "dmg" else {
            try body(image)
            return
        }
        let mountPoint = paths.downloadsDirectory
            .appendingPathComponent("mount-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: mountPoint) }
        let attached = try await ProcessWaiter.runTool(
            "/usr/bin/hdiutil",
            ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mountPoint.path, image.path],
            log: log
        )
        guard attached == 0 else { throw LayerSourceError.cannotMount(name: image.lastPathComponent) }
        do {
            try body(mountPoint)
        } catch {
            _ = try? await ProcessWaiter.runTool("/usr/bin/hdiutil", ["detach", "-quiet", mountPoint.path], log: log)
            throw error
        }
        _ = try? await ProcessWaiter.runTool("/usr/bin/hdiutil", ["detach", "-quiet", mountPoint.path], log: log)
    }

    /// Copies a folder. `cp -c` asks APFS for clones, which share their data
    /// with the original until one of them changes; on other file systems
    /// the plain copy below is used.
    private func cloneTree(from source: URL, to destination: URL) async throws {
        let cloned = try await ProcessWaiter.runTool("/bin/cp", ["-Rc", source.path, destination.path], log: log)
        if cloned == 0 { return }
        try? fileManager.removeItem(at: destination)
        let copied = try await ProcessWaiter.runTool("/bin/cp", ["-R", source.path, destination.path], log: log)
        guard copied == 0 else { throw WineInstallError.extractionFailed(name: layer.name, status: copied) }
    }

    // MARK: Kelter's Wine files

    /// Checks that Kelter's changed Wine files the layer needs fit the
    /// configured Wine and exist. Returns their folder, or `nil` if the
    /// layer needs none.
    @discardableResult
    public static func checkWineFiles(
        layer: RuntimeConfig.GraphicsLayer,
        patches: RuntimeConfig.WinePatches?,
        wine: RuntimeConfig.Wine,
        paths: AppPaths,
        fileManager: FileManager = .default
    ) throws -> URL? {
        guard let files = layer.wineFiles, !files.isEmpty else { return nil }
        guard let patches else { throw WineFilesError.notConfigured(layer: layer.name) }
        guard patches.wineVersion == wine.version else {
            throw WineFilesError.wrongWineVersion(
                name: patches.name, expected: patches.wineVersion, installed: wine.version)
        }
        let source = paths.wineFilesDirectory(wineVersion: patches.wineVersion, version: patches.version)
        var missing: [String] = []
        for file in files {
            let url = source.appendingPathComponent(try ArchiveInstaller.safeRelativePath(file))
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) || isDirectory.boolValue {
                missing.append(file)
            }
        }
        guard missing.isEmpty else {
            throw WineFilesError.missing(
                name: patches.name, layer: layer.name, files: missing, buildScript: patches.buildScript)
        }
        return source
    }

    /// Copies the changed Wine files the layer needs over the ones in
    /// `wineLibraries` (a copy's `lib/wine`). Returns the number of files.
    static func installWineFiles(
        layer: RuntimeConfig.GraphicsLayer,
        patches: RuntimeConfig.WinePatches?,
        wine: RuntimeConfig.Wine,
        paths: AppPaths,
        into wineLibraries: URL,
        fileManager: FileManager
    ) throws -> Int {
        guard let files = layer.wineFiles,
              let source = try checkWineFiles(
                layer: layer, patches: patches, wine: wine, paths: paths, fileManager: fileManager)
        else { return 0 }
        for file in files {
            let relative = try ArchiveInstaller.safeRelativePath(file)
            let destination = wineLibraries.appendingPathComponent(relative)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fileManager.attributesOfItem(atPath: destination.path)) != nil {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source.appendingPathComponent(relative), to: destination)
        }
        return files.count
    }

    // MARK: Bottle

    /// Puts the layer's libraries that a bottle does not have yet into the
    /// bottle's Windows folders. Wine loads a built-in library only if a
    /// file of that name exists in the prefix; libraries a layer adds
    /// (DXMT's `winemetal.dll`) are missing in a prefix made by plain Wine.
    /// Existing files stay untouched. Returns the names that were added.
    @discardableResult
    public static func installPrefixLibraries(
        layer: RuntimeConfig.GraphicsLayer,
        paths: AppPaths,
        prefix: URL,
        fileManager: FileManager = .default
    ) throws -> [String] {
        guard let folders = layer.prefixLibraries, !folders.isEmpty else { return [] }
        let layerFiles = try layerFilesDirectory(paths: paths, layer: layer)
        var added: [String] = []
        for (sourceFolder, targetFolder) in folders.sorted(by: { $0.key < $1.key }) {
            let source = layerFiles
                .appendingPathComponent(try ArchiveInstaller.safeRelativePath(sourceFolder), isDirectory: true)
            let target = prefix
                .appendingPathComponent(try ArchiveInstaller.safeRelativePath(targetFolder), isDirectory: true)
            // A prefix that Wine has not set up yet gets its files later.
            guard fileManager.fileExists(atPath: target.path),
                  let names = try? fileManager.contentsOfDirectory(atPath: source.path)
            else { continue }
            for name in names.sorted() where name.lowercased().hasSuffix(".dll") {
                let destination = target.appendingPathComponent(name)
                if (try? fileManager.attributesOfItem(atPath: destination.path)) != nil { continue }
                try fileManager.copyItem(at: source.appendingPathComponent(name), to: destination)
                added.append("\(targetFolder)/\(name)")
            }
        }
        return added
    }

    /// Copies every file and symbolic link below `source` to the same
    /// relative path below `target`, replacing what is there. Links stay
    /// links (a framework needs its `Versions/Current`). Returns the number
    /// of files and links.
    static func overlay(from source: URL, onto target: URL, fileManager: FileManager) throws -> Int {
        guard let enumerator = fileManager.enumerator(atPath: source.path) else { return 0 }
        var count = 0
        while let relative = enumerator.nextObject() as? String {
            let from = source.appendingPathComponent(relative)
            // attributesOfItem does not follow symbolic links.
            guard let type = (try? fileManager.attributesOfItem(atPath: from.path))?[.type] as? FileAttributeType,
                  type == .typeRegular || type == .typeSymbolicLink
            else { continue }
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
