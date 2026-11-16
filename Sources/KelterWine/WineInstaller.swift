import CryptoKit
import Foundation
import KelterCore

public enum WineInstallPhase: Equatable, Sendable {
    /// Fraction 0…1, or `nil` if the server did not say how big the file is.
    case downloading(Double?)
    case verifying
    case extracting
}

public enum WineInstallError: LocalizedError, Equatable {
    case checksumMismatch(name: String, expected: String, actual: String)
    case extractionFailed(name: String, status: Int32)
    case binaryMissing(String)
    case unsafePath(String)

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch(let name, let expected, let actual):
            return loc("Die Prüfsumme von %@ stimmt nicht.\nErwartet: %@\nErhalten: %@", "\(name)", "\(expected)", "\(actual)")
        case .extractionFailed(let name, let status):
            return loc("%@ konnte nicht entpackt werden (tar-Status %@).", "\(name)", "\(status)")
        case .binaryMissing(let path):
            return loc("Nach dem Entpacken fehlt %@. Passen die Pfade in runtimes.json zum Archiv?", "\(path)")
        case .unsafePath(let path):
            return loc("Der Pfad \"%@\" in runtimes.json ist nicht zulässig.", "\(path)")
        }
    }
}

/// One downloadable `.tar.*` archive that is unpacked into its own folder.
struct ArchivePackage {
    var name: String
    var version: String
    var url: URL
    var sha256: String?
    /// Folder the archive's content ends up in, e.g. `Runtimes/wine/<version>`.
    var target: URL
    /// Paths relative to `target` that are deleted after unpacking.
    var removeAfterInstall: [String] = []
}

/// Downloads, verifies and unpacks an `ArchivePackage`.
struct ArchiveInstaller {
    let paths: AppPaths
    let log: LogFile

    func install(
        _ package: ArchivePackage,
        onPhase: @escaping @Sendable (WineInstallPhase) -> Void
    ) async throws {
        let fileManager = FileManager.default
        try paths.ensureDirectories()
        // Check the paths before spending minutes on a download.
        let removals = try package.removeAfterInstall.map { try Self.safeRelativePath($0) }

        let archive = paths.downloadsDirectory.appendingPathComponent(package.url.lastPathComponent)

        // Reuse an archive from an earlier attempt if it is intact.
        var needsDownload = true
        if fileManager.fileExists(atPath: archive.path), let expected = package.sha256 {
            onPhase(.verifying)
            let actual = try Self.sha256(of: archive)
            needsDownload = actual.caseInsensitiveCompare(expected) != .orderedSame
        }

        if needsDownload {
            log.append("\nLade \(package.name) \(package.version) von \(package.url.absoluteString)\n")
            onPhase(.downloading(0))
            let downloader = FileDownloader(destination: archive) { fraction in
                onPhase(.downloading(fraction))
            }
            try await downloader.download(from: package.url)

            if let expected = package.sha256 {
                onPhase(.verifying)
                let actual = try Self.sha256(of: archive)
                guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                    try? fileManager.removeItem(at: archive)
                    throw WineInstallError.checksumMismatch(name: package.name, expected: expected, actual: actual)
                }
                log.append("Prüfsumme stimmt.\n")
            }
        }

        onPhase(.extracting)
        let target = package.target
        // Unpack next to the final location and swap it in at the end, so a
        // cancelled run never leaves a half-unpacked folder that looks complete.
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(package.version + ".partial", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        let tarStatus = try await ProcessWaiter.runTool(
            "/usr/bin/tar",
            ["-xf", archive.path, "-C", staging.path],
            log: log
        )
        guard tarStatus == 0 else {
            try? fileManager.removeItem(at: staging)
            throw WineInstallError.extractionFailed(name: package.name, status: tarStatus)
        }

        for relativePath in removals {
            let unwanted = staging.appendingPathComponent(relativePath)
            // attributesOfItem does not follow symbolic links.
            if (try? fileManager.attributesOfItem(atPath: unwanted.path)) != nil {
                try fileManager.removeItem(at: unwanted)
                log.append("Entfernt: \(relativePath)\n")
            }
        }

        // Files fetched by Kelter are normally not quarantined; this is a
        // cheap safeguard so Gatekeeper never blocks the unpacked binaries.
        _ = try? await ProcessWaiter.runTool(
            "/usr/bin/xattr",
            ["-dr", "com.apple.quarantine", staging.path],
            log: log
        )

        try? fileManager.removeItem(at: target)
        try fileManager.moveItem(at: staging, to: target)
        // The archive is large and no longer needed.
        try? fileManager.removeItem(at: archive)
    }

    /// Deletes the other versions next to `target` (for example an older
    /// Wine), which Kelter downloaded itself and can download again.
    func removeOtherVersions(besides target: URL) {
        let fileManager = FileManager.default
        let parent = target.deletingLastPathComponent()
        guard let siblings = try? fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for sibling in siblings where sibling.lastPathComponent != target.lastPathComponent {
            do {
                try fileManager.removeItem(at: sibling)
                log.append("Alte Version entfernt: \(sibling.path)\n")
            } catch {
                log.append("Alte Version konnte nicht entfernt werden: \(sibling.path)\n")
            }
        }
    }

    /// A path from runtimes.json must stay inside the folder it refers to.
    static func safeRelativePath(_ path: String) throws -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !path.hasPrefix("/"), !components.isEmpty, !components.contains(".."), !components.contains(".") else {
            throw WineInstallError.unsafePath(path)
        }
        return components.joined(separator: "/")
    }

    /// SHA-256 of a file as lowercase hex, read in chunks.
    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Downloads the Wine build named in `runtimes.json`, checks it and unpacks
/// it below `Runtimes/wine/<version>/`.
public final class WineInstaller: @unchecked Sendable {
    private let paths: AppPaths
    private let config: RuntimeConfig.Wine
    private let log: LogFile

    public init(paths: AppPaths, config: RuntimeConfig.Wine, log: LogFile) {
        self.paths = paths
        self.config = config
        self.log = log
    }

    public func install(
        onPhase: @escaping @Sendable (WineInstallPhase) -> Void
    ) async throws -> WineInstallation {
        let installer = ArchiveInstaller(paths: paths, log: log)
        let target = paths.wineDirectory(version: config.version)
        try await installer.install(
            ArchivePackage(
                name: config.name,
                version: config.version,
                url: config.url,
                sha256: config.sha256,
                target: target
            ),
            onPhase: onPhase
        )
        guard let installation = WineInstallation.locate(paths: paths, config: config) else {
            let expected = WineInstallation.expected(paths: paths, config: config)
            throw WineInstallError.binaryMissing(expected.wine.path)
        }
        installer.removeOtherVersions(besides: target)
        log.append("Wine \(config.version) ist installiert: \(installation.root.path)\n")
        return installation
    }

    /// SHA-256 of a file as lowercase hex.
    static func sha256(of file: URL) throws -> String {
        try ArchiveInstaller.sha256(of: file)
    }
}

/// Downloads the support package (runtime libraries and renderers) named in
/// `runtimes.json` and unpacks it below `Runtimes/support/<version>/`.
public final class SupportInstaller: @unchecked Sendable {
    private let paths: AppPaths
    private let config: RuntimeConfig.Support
    private let log: LogFile

    public init(paths: AppPaths, config: RuntimeConfig.Support, log: LogFile) {
        self.paths = paths
        self.config = config
        self.log = log
    }

    public func install(
        onPhase: @escaping @Sendable (WineInstallPhase) -> Void
    ) async throws -> SupportInstallation {
        let installer = ArchiveInstaller(paths: paths, log: log)
        let target = paths.supportDirectory(version: config.version)
        // `removeAfterInstall` is relative to the archive root.
        let root = try ArchiveInstaller.safeRelativePath(config.archiveRoot)
        try await installer.install(
            ArchivePackage(
                name: config.name,
                version: config.version,
                url: config.url,
                sha256: config.sha256,
                target: target,
                removeAfterInstall: config.removeAfterInstall.map { root + "/" + $0 }
            ),
            onPhase: onPhase
        )
        guard let installation = SupportInstallation.locate(paths: paths, config: config) else {
            let expected = SupportInstallation.expected(paths: paths, config: config)
            throw WineInstallError.binaryMissing(expected.libraryDirectories.first?.path ?? expected.root.path)
        }
        installer.removeOtherVersions(besides: target)
        log.append("\(config.name) \(config.version) ist installiert: \(installation.root.path)\n")
        return installation
    }
}
