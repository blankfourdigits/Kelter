import Foundation
import XCTest
import KelterCore
@testable import KelterSteam

final class SteamTests: XCTestCase {
    private func steamConfig(defaultArguments: [String] = ["-cef-in-process-gpu"]) -> RuntimeConfig.Steam {
        RuntimeConfig.Steam(
            installerURL: URL(string: "https://example.invalid/SteamSetup.exe")!,
            installerArguments: ["/S"],
            executablePath: "Program Files (x86)/Steam/steam.exe",
            defaultArguments: defaultArguments,
            argumentPresets: [],
            uiFix: RuntimeConfig.Steam.UIFix(
                enabled: true,
                library: "steam-ui-fix/winmm.dll",
                builtinLibrary: "wine/x86_64-windows/winmm.dll",
                browserArguments: ["--in-process-gpu"]
            )
        )
    }

    func testExecutableLocation() {
        let prefix = URL(fileURLWithPath: "/tmp/Kelter/Bottles/abc/prefix")
        let config = steamConfig()

        XCTAssertEqual(
            SteamLocation.executable(prefix: prefix, config: config).path,
            "/tmp/Kelter/Bottles/abc/prefix/drive_c/Program Files (x86)/Steam/steam.exe"
        )
        XCTAssertEqual(
            SteamLocation.directory(prefix: prefix, config: config).path,
            "/tmp/Kelter/Bottles/abc/prefix/drive_c/Program Files (x86)/Steam"
        )
    }

    func testIsInstalledChecksForSteamExe() throws {
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterSteam-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: prefix) }
        let config = steamConfig()

        XCTAssertFalse(SteamLocation.isInstalled(prefix: prefix, config: config))

        let executable = SteamLocation.executable(prefix: prefix, config: config)
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: executable)

        XCTAssertTrue(SteamLocation.isInstalled(prefix: prefix, config: config))
    }

    func testArgumentsFallBackToDefaults() {
        let config = steamConfig(defaultArguments: ["-a", "-b"])
        XCTAssertEqual(SteamLauncher.arguments(for: BottleSettings(), config: config), ["-a", "-b"])
    }

    func testBottleArgumentsReplaceDefaults() {
        let config = steamConfig(defaultArguments: ["-a", "-b"])
        var settings = BottleSettings()

        settings.steamArguments = ["-c"]
        XCTAssertEqual(SteamLauncher.arguments(for: settings, config: config), ["-c"])

        // An explicitly empty list means "no parameters", not "defaults".
        settings.steamArguments = []
        XCTAssertEqual(SteamLauncher.arguments(for: settings, config: config), [])
    }
}

final class SteamUIFixTests: XCTestCase {
    private var root: URL!
    private var prefix: URL!
    private var helper: URL!
    private var builtin: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterUIFix-\(UUID().uuidString)", isDirectory: true)
        prefix = root.appendingPathComponent("bottle/prefix", isDirectory: true)
        helper = root.appendingPathComponent("resources/winmm.dll")
        builtin = root.appendingPathComponent("wine/winmm.dll")
        for folder in [helper.deletingLastPathComponent(), builtin.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("helper".utf8).write(to: helper)
        try Data("builtin".utf8).write(to: builtin)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var system32: URL {
        prefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
    }

    private func contents(_ name: String) throws -> String {
        try String(contentsOf: system32.appendingPathComponent(name), encoding: .utf8)
    }

    func testInstallFilesPutsHelperInPlaceAndKeepsOriginal() throws {
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
        try Data("old winmm".utf8).write(to: system32.appendingPathComponent("winmm.dll"))
        let fix = SteamUIFix(helperLibrary: helper, builtinLibrary: builtin)

        try fix.installFiles(prefix: prefix)

        XCTAssertEqual(try contents("winmm.dll"), "helper")
        XCTAssertEqual(try contents("winmm_orig.dll"), "builtin")
        // The sources are copied, not moved.
        XCTAssertTrue(FileManager.default.fileExists(atPath: helper.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: builtin.path))
    }

    func testInstallFilesCanBeRepeated() throws {
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
        let fix = SteamUIFix(helperLibrary: helper, builtinLibrary: builtin)

        try fix.installFiles(prefix: prefix)
        try fix.installFiles(prefix: prefix)

        XCTAssertEqual(try contents("winmm.dll"), "helper")
        XCTAssertEqual(try contents("winmm_orig.dll"), "builtin")
    }

    func testInstallFilesReplacesALinkWithoutTouchingItsTarget() throws {
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
        // Some Wine set-ups link system32 files to the Wine installation.
        try FileManager.default.createSymbolicLink(
            at: system32.appendingPathComponent("winmm.dll"),
            withDestinationURL: builtin
        )
        let fix = SteamUIFix(helperLibrary: helper, builtinLibrary: builtin)

        try fix.installFiles(prefix: prefix)

        XCTAssertEqual(try contents("winmm.dll"), "helper")
        XCTAssertEqual(try String(contentsOf: builtin, encoding: .utf8), "builtin")
    }

    func testInstallFilesFailsBeforeChangingAnythingWhenAFileIsMissing() throws {
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
        try Data("old winmm".utf8).write(to: system32.appendingPathComponent("winmm.dll"))
        let missing = root.appendingPathComponent("resources/missing.dll")
        let fix = SteamUIFix(helperLibrary: missing, builtinLibrary: builtin)

        XCTAssertThrowsError(try fix.installFiles(prefix: prefix)) { error in
            XCTAssertEqual(error as? SteamUIFixError, .missingFile(missing.path))
        }
        XCTAssertEqual(try contents("winmm.dll"), "old winmm")
        XCTAssertFalse(FileManager.default.fileExists(atPath: system32.appendingPathComponent("winmm_orig.dll").path))
    }

    func testInstallFilesNeedsAnInitializedPrefix() {
        let fix = SteamUIFix(helperLibrary: helper, builtinLibrary: builtin)
        XCTAssertThrowsError(try fix.installFiles(prefix: prefix)) { error in
            XCTAssertEqual(error as? SteamUIFixError, .prefixNotInitialized(system32.path))
        }
    }

    func testEnvironmentCarriesBrowserArguments() {
        XCTAssertEqual(
            SteamUIFix.environment(browserArguments: ["--in-process-gpu", "--disable-gpu"]),
            ["KELTER_CEF_APPEND": "--in-process-gpu --disable-gpu"]
        )
        // No arguments: tell the helper to do nothing.
        XCTAssertEqual(SteamUIFix.environment(browserArguments: []), ["KELTER_CEF_APPEND": "-"])
    }

    func testMarkerLivesNextToThePrefix() {
        XCTAssertEqual(
            SteamUIFix.marker(prefix: prefix).path,
            root.appendingPathComponent("bottle/steam-ui-fix-registered").path
        )
        XCTAssertFalse(SteamUIFix.isRegistered(prefix: prefix))
    }
}
