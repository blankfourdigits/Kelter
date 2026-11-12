import Foundation
import KelterCore

/// Builds the environment a Wine process runs with. Pure function, so it can
/// be tested without Wine.
public enum WineEnvironment {
    /// WINEDEBUG value for a bottle with verbose logging: every line gets a
    /// time and process id, and Wine reports loaded libraries, exceptions and
    /// (by not switching them off) calls to unimplemented functions.
    public static let verboseDebugChannels = "+timestamp,+pid,+loaddll,+seh"

    /// Order of precedence, lowest first: inherited environment, Kelter's own
    /// values, the bottle's `environment`, `extra`.
    public static func make(
        base: [String: String],
        prefix: URL,
        settings: BottleSettings,
        wine: RuntimeConfig.Wine,
        support: SupportInstallation? = nil,
        extra: [String: String] = [:]
    ) -> [String: String] {
        // Xcode injects DYLD_* variables (debugging libraries built for arm64)
        // into the app it runs. Wine is an Intel process and must not inherit
        // them. A bottle can still set such a variable on purpose.
        var environment = base.filter { key, _ in
            !key.hasPrefix("DYLD_") && !key.hasPrefix("__XPC_DYLD_")
        }

        environment["WINEPREFIX"] = prefix.path
        if settings.verboseLogging {
            environment["WINEDEBUG"] = verboseDebugChannels
        } else if environment["WINEDEBUG"] == nil {
            // Keep errors and warnings, drop the very chatty "fixme" lines.
            environment["WINEDEBUG"] = "fixme-all"
        }

        environment["WINEDLLOVERRIDES"] = dllOverridesString(mergedDllOverrides(settings: settings))

        if let support {
            applySupport(support, backend: settings.graphicsBackend, to: &environment)
        }

        if settings.metalHUD {
            environment["MTL_HUD_ENABLED"] = "1"
        }
        if settings.esync && wine.supportsESync {
            environment["WINEESYNC"] = "1"
        }
        if settings.msync && wine.supportsMSync {
            environment["WINEMSYNC"] = "1"
        }

        for (key, value) in settings.environment {
            environment[key] = value
        }
        for (key, value) in extra {
            environment[key] = value
        }
        return environment
    }

    /// Tells Wine where its run-time libraries, the Vulkan driver and the
    /// chosen Direct3D renderers are.
    private static func applySupport(
        _ support: SupportInstallation,
        backend: GraphicsBackendKind,
        to environment: inout [String: String]
    ) {
        // macOS looks here for libraries Wine loads by name (FreeType,
        // GnuTLS, the Vulkan loader …). /usr/lib keeps the system default.
        let libraries = support.libraryDirectories.map(\.path) + ["/usr/lib"]
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = libraries.joined(separator: ":")

        if let plugins = support.gstreamerPluginDirectory {
            environment["GST_PLUGIN_PATH"] = plugins.path
        }
        if let driver = support.vulkanDriverFile {
            // Current and older name of the same Vulkan loader setting.
            environment["VK_DRIVER_FILES"] = driver.path
            environment["VK_ICD_FILENAMES"] = driver.path
        }
        for id in backend.rendererIDs {
            if let renderer = support.renderer(id: id) {
                environment[renderer.variable] = renderer.directory.path
            }
        }
        for (key, value) in support.config.environment {
            environment[key] = value
        }
    }

    /// Kelter's defaults, then `additional` (for example Steam's overrides
    /// from runtimes.json), then the bottle's own, which win.
    public static func mergedDllOverrides(
        settings: BottleSettings,
        additional: [String: String] = [:]
    ) -> [String: String] {
        // Stop Wine from creating launchers and file associations on the Mac.
        var overrides = ["winemenubuilder.exe": "d"]
        for (name, mode) in additional {
            overrides[name] = mode
        }
        for (name, mode) in settings.dllOverrides {
            overrides[name] = mode
        }
        return overrides
    }

    /// `["d3d11": "n,b", "dxgi": "n"]` becomes `d3d11=n,b;dxgi=n` (sorted, so
    /// the result is stable).
    public static func dllOverridesString(_ overrides: [String: String]) -> String {
        overrides
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ";")
    }
}
