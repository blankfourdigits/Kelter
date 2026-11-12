import Foundation
import KelterCore

/// Where the Windows Steam client lives inside a bottle.
public enum SteamLocation {
    /// `<prefix>/drive_c/Program Files (x86)/Steam/steam.exe` with the default
    /// configuration.
    public static func executable(prefix: URL, config: RuntimeConfig.Steam) -> URL {
        prefix
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent(config.executablePath)
    }

    /// The folder that contains `steam.exe` (and `steamapps`).
    public static func directory(prefix: URL, config: RuntimeConfig.Steam) -> URL {
        executable(prefix: prefix, config: config).deletingLastPathComponent()
    }

    public static func isInstalled(
        prefix: URL,
        config: RuntimeConfig.Steam,
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: executable(prefix: prefix, config: config).path)
    }
}
