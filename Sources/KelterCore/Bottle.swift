import Foundation

/// Windows version a bottle reports to programs. Raw values are the names
/// `winecfg -v` accepts.
public enum WindowsVersion: String, Codable, CaseIterable, Sendable {
    case win11
    case win10
    case win81
    case win7

    public var displayName: String {
        switch self {
        case .win11: return "Windows 11"
        case .win10: return "Windows 10"
        case .win81: return "Windows 8.1"
        case .win7: return "Windows 7"
        }
    }
}

/// How Direct3D is translated for the Mac.
///
/// Every choice except `wined3d` also sends DirectX 8 and 9 through D9VK
/// (Vulkan), because none of the Metal layers handles those versions.
public enum GraphicsBackendKind: String, Codable, CaseIterable, Sendable {
    /// Wine's built-in translation (OpenGL). Slowest, but needs nothing else.
    case wined3d
    /// DirectX 10/11 through Metal. The default.
    case dxmt
    /// Apple's layer from the Game Porting Toolkit: DirectX 11/12, 64-bit only.
    case d3dmetal
    /// DirectX 10/11 through Vulkan (MoltenVK).
    case dxvk

    public var displayName: String {
        switch self {
        case .wined3d: return "Wine (eingebaut)"
        case .dxmt: return "DXMT (DirectX 10/11 über Metal)"
        case .d3dmetal: return "D3DMetal (DirectX 11/12, Apple)"
        case .dxvk: return "DXVK (DirectX 10/11 über Vulkan)"
        }
    }

    /// The renderers from the support package this choice switches on, as
    /// ids used in runtimes.json.
    public var rendererIDs: [String] {
        switch self {
        case .wined3d: return []
        case .dxmt: return ["d9vk", "dxmt"]
        case .dxvk: return ["d9vk", "dxvk"]
        // DXMT stays on for 32-bit programs, which D3DMetal cannot run.
        case .d3dmetal: return ["d9vk", "dxmt", "d3dmetal"]
        }
    }
}

public struct BottleSettings: Codable, Equatable, Sendable {
    public var windowsVersion: WindowsVersion
    public var graphicsBackend: GraphicsBackendKind
    /// Extra environment variables. They win over everything Kelter sets.
    public var environment: [String: String]
    /// DLL name to load order, e.g. `"d3d11": "n,b"`.
    public var dllOverrides: [String: String]
    public var esync: Bool
    public var msync: Bool
    public var metalHUD: Bool
    public var retinaMode: Bool
    /// Start parameters for the Steam client in this bottle. `nil` means
    /// "use the defaults from runtimes.json".
    public var steamArguments: [String]?
    /// Chromium switches for Steam's browser process in this bottle. `nil`
    /// means "use the defaults from runtimes.json".
    public var steamBrowserArguments: [String]?
    /// Makes Wine log much more (loaded libraries, exceptions, unimplemented
    /// functions). For tracking down why a program does not start.
    public var verboseLogging: Bool

    public init(
        windowsVersion: WindowsVersion = .win10,
        graphicsBackend: GraphicsBackendKind = .dxmt,
        environment: [String: String] = [:],
        dllOverrides: [String: String] = [:],
        esync: Bool = false,
        msync: Bool = false,
        metalHUD: Bool = false,
        retinaMode: Bool = false,
        steamArguments: [String]? = nil,
        steamBrowserArguments: [String]? = nil,
        verboseLogging: Bool = false
    ) {
        self.windowsVersion = windowsVersion
        self.graphicsBackend = graphicsBackend
        self.environment = environment
        self.dllOverrides = dllOverrides
        self.esync = esync
        self.msync = msync
        self.metalHUD = metalHUD
        self.retinaMode = retinaMode
        self.steamArguments = steamArguments
        self.steamBrowserArguments = steamBrowserArguments
        self.verboseLogging = verboseLogging
    }

    private enum CodingKeys: String, CodingKey {
        case windowsVersion
        case graphicsBackend
        case environment
        case dllOverrides
        case esync
        case msync
        case metalHUD
        case retinaMode
        case steamArguments
        case steamBrowserArguments
        case verboseLogging
    }

    /// Missing keys fall back to defaults, so a `bottle.json` written by an
    /// older version of Kelter still loads after new settings are added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BottleSettings()
        windowsVersion = try container.decodeIfPresent(WindowsVersion.self, forKey: .windowsVersion)
            ?? defaults.windowsVersion
        graphicsBackend = try container.decodeIfPresent(GraphicsBackendKind.self, forKey: .graphicsBackend)
            ?? defaults.graphicsBackend
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment)
            ?? defaults.environment
        dllOverrides = try container.decodeIfPresent([String: String].self, forKey: .dllOverrides)
            ?? defaults.dllOverrides
        esync = try container.decodeIfPresent(Bool.self, forKey: .esync) ?? defaults.esync
        msync = try container.decodeIfPresent(Bool.self, forKey: .msync) ?? defaults.msync
        metalHUD = try container.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? defaults.metalHUD
        retinaMode = try container.decodeIfPresent(Bool.self, forKey: .retinaMode) ?? defaults.retinaMode
        steamArguments = try container.decodeIfPresent([String].self, forKey: .steamArguments)
        steamBrowserArguments = try container.decodeIfPresent([String].self, forKey: .steamBrowserArguments)
        verboseLogging = try container.decodeIfPresent(Bool.self, forKey: .verboseLogging) ?? defaults.verboseLogging
    }
}

/// One isolated Windows environment (a Wine prefix plus Kelter's settings).
public struct Bottle: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var settings: BottleSettings

    public init(id: UUID = UUID(), name: String, createdAt: Date, settings: BottleSettings = BottleSettings()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.settings = settings
    }
}
