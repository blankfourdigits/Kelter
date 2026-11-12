import Foundation
import KelterCore

public enum WineRunnerError: LocalizedError, Equatable {
    case commandFailed(command: String, status: Int32)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let status):
            return "\"\(command)\" ist mit Status \(status) fehlgeschlagen. Details stehen im Log."
        }
    }
}

/// The only place in Kelter that starts Wine.
///
/// Every call sets `WINEPREFIX` and the bottle's environment, and sends the
/// output of the process to the log file.
public final class WineRunner: @unchecked Sendable {
    public let installation: WineInstallation
    public let config: RuntimeConfig.Wine
    /// Run-time libraries and renderers, if the Wine build needs them.
    public let support: SupportInstallation?
    public let log: LogFile

    public init(
        installation: WineInstallation,
        config: RuntimeConfig.Wine,
        support: SupportInstallation? = nil,
        log: LogFile
    ) {
        self.installation = installation
        self.config = config
        self.support = support
        self.log = log
    }

    // MARK: Running

    /// Runs `wine <arguments>` in the given prefix and waits until it exits.
    /// Returns the exit status.
    @discardableResult
    public func run(
        _ arguments: [String],
        prefix: URL,
        settings: BottleSettings,
        extraEnvironment: [String: String] = [:],
        workingDirectory: URL? = nil
    ) async throws -> Int32 {
        try await launch(
            executable: installation.wine,
            label: "wine",
            arguments: arguments,
            prefix: prefix,
            settings: settings,
            extraEnvironment: extraEnvironment,
            workingDirectory: workingDirectory
        )
    }

    /// Starts a Windows program or installer that lives somewhere on the Mac.
    @discardableResult
    public func runFile(_ file: URL, prefix: URL, settings: BottleSettings) async throws -> Int32 {
        let folder = file.deletingLastPathComponent()
        if file.pathExtension.lowercased() == "msi" {
            // msiexec wants a Windows style path; a bare file name relative
            // to the working directory avoids any path conversion.
            return try await run(
                ["msiexec", "/i", file.lastPathComponent],
                prefix: prefix,
                settings: settings,
                workingDirectory: folder
            )
        }
        return try await run([file.path], prefix: prefix, settings: settings, workingDirectory: folder)
    }

    // MARK: Prefix management

    /// Creates the Wine prefix (or updates an existing one) and applies the
    /// bottle's settings.
    public func initializePrefix(prefix: URL, settings: BottleSettings) async throws {
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let status = try await run(["wineboot", "--init"], prefix: prefix, settings: settings)
        guard status == 0 else {
            throw WineRunnerError.commandFailed(command: "wineboot --init", status: status)
        }
        try await applySettings(prefix: prefix, settings: settings)
    }

    /// Writes the settings that live inside the prefix (registry), as opposed
    /// to those that are plain environment variables.
    public func applySettings(prefix: URL, settings: BottleSettings) async throws {
        let versionStatus = try await run(
            ["winecfg", "-v", settings.windowsVersion.rawValue],
            prefix: prefix,
            settings: settings
        )
        guard versionStatus == 0 else {
            throw WineRunnerError.commandFailed(command: "winecfg -v", status: versionStatus)
        }

        let retinaStatus = try await run(
            [
                "reg", "add", "HKCU\\Software\\Wine\\Mac Driver",
                "/v", "RetinaMode",
                "/t", "REG_SZ",
                "/d", settings.retinaMode ? "y" : "n",
                "/f",
            ],
            prefix: prefix,
            settings: settings
        )
        guard retinaStatus == 0 else {
            throw WineRunnerError.commandFailed(command: "reg add RetinaMode", status: retinaStatus)
        }
    }

    /// Ends every Wine process of this prefix (`wineserver -k`).
    /// A non-zero status only means nothing was running.
    @discardableResult
    public func killAll(prefix: URL, settings: BottleSettings) async throws -> Int32 {
        try await launch(
            executable: installation.wineserver,
            label: "wineserver",
            arguments: ["-k"],
            prefix: prefix,
            settings: settings,
            extraEnvironment: [:],
            workingDirectory: nil
        )
    }

    // MARK: Internals

    private func launch(
        executable: URL,
        label: String,
        arguments: [String],
        prefix: URL,
        settings: BottleSettings,
        extraEnvironment: [String: String],
        workingDirectory: URL?
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = WineEnvironment.make(
            base: ProcessInfo.processInfo.environment,
            prefix: prefix,
            settings: settings,
            wine: config,
            support: support,
            extra: extraEnvironment
        )
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        let output = try log.openForAppending()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice

        log.append("\n$ \(label) \(arguments.joined(separator: " "))\n")
        let status = try await ProcessWaiter.run(process)
        log.append("[\(label) beendet mit Status \(status)]\n")
        return status
    }
}
