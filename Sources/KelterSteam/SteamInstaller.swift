import Foundation
import KelterCore
import KelterWine

public enum SteamInstallPhase: Equatable, Sendable {
    case downloading
    case installing
}

public enum SteamError: LocalizedError, Equatable {
    case installerFailed(status: Int32)
    case notInstalled

    public var errorDescription: String? {
        switch self {
        case .installerFailed(let status):
            return "Der Steam-Installer ist mit Status \(status) fehlgeschlagen. Details stehen im Log."
        case .notInstalled:
            return "Steam ist in dieser Bottle nicht installiert."
        }
    }
}

/// Downloads Valve's Windows installer and runs it unattended in a bottle.
public final class SteamInstaller: @unchecked Sendable {
    private let paths: AppPaths
    private let config: RuntimeConfig.Steam
    private let runner: WineRunner
    private let log: LogFile

    public init(paths: AppPaths, config: RuntimeConfig.Steam, runner: WineRunner, log: LogFile) {
        self.paths = paths
        self.config = config
        self.runner = runner
        self.log = log
    }

    public func install(
        prefix: URL,
        settings: BottleSettings,
        onPhase: @escaping @Sendable (SteamInstallPhase) -> Void
    ) async throws {
        try paths.ensureDirectories()
        let installer = paths.downloadsDirectory.appendingPathComponent("SteamSetup.exe")

        // The installer is only a few MB and changes over time, so it is
        // always fetched fresh.
        onPhase(.downloading)
        log.append("\nLade den Steam-Installer von \(config.installerURL.absoluteString)\n")
        let downloader = FileDownloader(destination: installer) { _ in }
        try await downloader.download(from: config.installerURL)

        onPhase(.installing)
        let status = try await runner.run(
            [installer.path] + config.installerArguments,
            prefix: prefix,
            settings: settings,
            workingDirectory: paths.downloadsDirectory
        )
        try? FileManager.default.removeItem(at: installer)

        // What counts is whether steam.exe is there, not the exit status:
        // installers under Wine sometimes report odd codes after succeeding.
        guard SteamLocation.isInstalled(prefix: prefix, config: config) else {
            throw SteamError.installerFailed(status: status)
        }
        log.append("Steam ist installiert: \(SteamLocation.executable(prefix: prefix, config: config).path)\n")
    }
}
