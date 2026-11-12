import Foundation
import KelterCore
import KelterWine

/// Starts and stops the Steam client of a bottle.
public final class SteamLauncher: @unchecked Sendable {
    private let config: RuntimeConfig.Steam
    private let runner: WineRunner

    public init(config: RuntimeConfig.Steam, runner: WineRunner) {
        self.config = config
        self.runner = runner
    }

    /// The bottle's own start parameters, or the defaults from runtimes.json.
    public static func arguments(for settings: BottleSettings, config: RuntimeConfig.Steam) -> [String] {
        settings.steamArguments ?? config.defaultArguments
    }

    /// Starts Steam and waits until this `steam.exe` process ends. Steam may
    /// restart itself during an update, so returning does not mean Steam has
    /// quit.
    @discardableResult
    public func launch(
        prefix: URL,
        settings: BottleSettings,
        extraArguments: [String] = [],
        environment: [String: String] = [:]
    ) async throws -> Int32 {
        guard SteamLocation.isInstalled(prefix: prefix, config: config) else {
            throw SteamError.notInstalled
        }
        let executable = SteamLocation.executable(prefix: prefix, config: config)
        let arguments = Self.arguments(for: settings, config: config) + extraArguments
        return try await runner.run(
            [executable.path] + arguments,
            prefix: prefix,
            settings: settings,
            extraEnvironment: environment,
            workingDirectory: executable.deletingLastPathComponent()
        )
    }

    /// Asks Steam to quit, gives it a moment to save, then ends every Wine
    /// process of the bottle so nothing keeps running in the background.
    public func shutdown(
        prefix: URL,
        settings: BottleSettings,
        gracePeriodSeconds: UInt64 = 6
    ) async {
        if SteamLocation.isInstalled(prefix: prefix, config: config) {
            let executable = SteamLocation.executable(prefix: prefix, config: config)
            let runner = self.runner
            // Not awaited: if Steam is not running, `-shutdown` may itself
            // hang. The `wineserver -k` below ends it either way.
            Task.detached {
                _ = try? await runner.run(
                    [executable.path, "-shutdown"],
                    prefix: prefix,
                    settings: settings,
                    workingDirectory: executable.deletingLastPathComponent()
                )
            }
            try? await Task.sleep(nanoseconds: gracePeriodSeconds * 1_000_000_000)
        }
        _ = try? await runner.killAll(prefix: prefix, settings: settings)
    }
}
