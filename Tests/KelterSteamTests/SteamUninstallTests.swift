import Foundation
import XCTest
import KelterCore
@testable import KelterSteam

final class SteamUninstallTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    /// Persona 5 Royal's install script as Steam installs it.
    static let p5rScript = """
        "InstallScript"
        {
        \t"Run Process On Uninstall"
        \t{
        \t\t"Process_name"
        \t\t{
        \t\t\t"process 1"\t\t"%INSTALLDIR%\\\\bin\\\\SaveRemoverTool.exe"
        \t\t\t"command 1"\t\t"-path \\"%APPDATA%/SEGA/P5R/Steam/\\""
        \t\t}
        \t}
        }
        """

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("kelter-uninstall-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private var prefix: URL { root.appendingPathComponent("prefix", isDirectory: true) }
    private var steam: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true) }
    private var user: URL { prefix.appendingPathComponent("drive_c/users/tester", isDirectory: true) }

    private func app(installDirectory: String = "P5R") -> SteamApp {
        SteamApp(appID: 1687950, name: "Persona 5 Royal", installDirectory: installDirectory,
                 library: steam, sizeOnDisk: 1, stateFlags: 4, lastPlayed: nil)
    }

    private func make(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func write(_ text: String, to url: URL) throws {
        try make(url.deletingLastPathComponent())
        try Data(text.utf8).write(to: url)
    }

    /// A bottle with P5R installed, its script, saves and Steam's leftovers.
    private func makeP5R() throws {
        try make(prefix.appendingPathComponent("drive_c/users/Public", isDirectory: true))
        try write("game", to: steam.appendingPathComponent("steamapps/common/P5R/P5R.exe"))
        try write(Self.p5rScript, to: steam.appendingPathComponent("steamapps/common/P5R/install.vdf"))
        try write("manifest", to: steam.appendingPathComponent("steamapps/appmanifest_1687950.acf"))
        try make(steam.appendingPathComponent("steamapps/shadercache/1687950", isDirectory: true))
        try write("save", to: user.appendingPathComponent("AppData/Roaming/SEGA/P5R/Steam/123/DATA.DAT"))
        try write("cloud", to: steam.appendingPathComponent("userdata/872884279/1687950/remote/x"))
        // Another game that must stay.
        try write("other", to: steam.appendingPathComponent("steamapps/common/Other/game.exe"))
        try write("other", to: steam.appendingPathComponent("steamapps/appmanifest_1.acf"))
    }

    func testPlanFindsGameFilesAndSaves() throws {
        try makeP5R()
        let plan = try SteamUninstall.plan(for: app(), steamDirectory: steam, prefix: prefix)
        let steamapps = steam.appendingPathComponent("steamapps")
        XCTAssertEqual(plan.gameItems.map(\.lastPathComponent), ["P5R", "appmanifest_1687950.acf", "1687950"])
        XCTAssertEqual(plan.gameItems[0].path, steamapps.appendingPathComponent("common/P5R").path)
        XCTAssertEqual(plan.saveFolders.map(\.path), [
            steam.appendingPathComponent("userdata/872884279/1687950").resolvingSymlinksInPath().path,
            user.appendingPathComponent("AppData/Roaming/SEGA/P5R/Steam").resolvingSymlinksInPath().path,
        ])
    }

    func testRemoveKeepsOtherGamesAndOptionallySaves() throws {
        try makeP5R()
        let plan = try SteamUninstall.plan(for: app(), steamDirectory: steam, prefix: prefix)
        try SteamUninstall.remove(plan.gameItems)
        XCTAssertFalse(fm.fileExists(atPath: steam.appendingPathComponent("steamapps/common/P5R").path))
        XCTAssertFalse(fm.fileExists(atPath: steam.appendingPathComponent("steamapps/appmanifest_1687950.acf").path))
        XCTAssertTrue(fm.fileExists(atPath: steam.appendingPathComponent("steamapps/common/Other/game.exe").path))
        XCTAssertTrue(fm.fileExists(atPath: steam.appendingPathComponent("steamapps/appmanifest_1.acf").path))
        // Saves stay unless asked for.
        XCTAssertTrue(fm.fileExists(atPath: user.appendingPathComponent("AppData/Roaming/SEGA/P5R/Steam").path))
        try SteamUninstall.remove(plan.saveFolders)
        XCTAssertFalse(fm.fileExists(atPath: user.appendingPathComponent("AppData/Roaming/SEGA/P5R/Steam").path))
        XCTAssertTrue(fm.fileExists(atPath: user.appendingPathComponent("AppData/Roaming/SEGA/P5R").path))
    }

    func testReadsTheUninstallScript() throws {
        let script = try VDF.parse(Self.p5rScript)
        XCTAssertEqual(SteamUninstall.uninstallPaths(in: script), ["%APPDATA%/SEGA/P5R/Steam/"])
    }

    func testFindsPathsInCommandLines() {
        XCTAssertEqual(SteamUninstall.folderPaths(in: #"-path "%APPDATA%/SEGA/P5R/Steam/""#),
                       ["%APPDATA%/SEGA/P5R/Steam/"])
        XCTAssertEqual(SteamUninstall.folderPaths(in: #"/clean %LOCALAPPDATA%\Studio\Game -q"#),
                       [#"%LOCALAPPDATA%\Studio\Game"#])
        // Only folder variables: %INSTALLDIR% belongs to the game itself.
        XCTAssertEqual(SteamUninstall.folderPaths(in: #""%INSTALLDIR%\bin\tool.exe" 50%"#), [])
    }

    func testRefusesBroadOrEscapingScriptPaths() throws {
        try make(user)
        try make(prefix.appendingPathComponent("drive_c/users/Public", isDirectory: true))
        for path in ["%APPDATA%", "%APPDATA%/SEGA", "%USERPROFILE%/Documents", "%APPDATA%/../../x/y",
                     "%APPDATA%/./a/b", "%SYSTEMROOT%/System32/x", "%INSTALLDIR%/a/b"] {
            XCTAssertNil(SteamUninstall.resolve(path, prefix: prefix, fileManager: fm), path)
        }
        XCTAssertEqual(SteamUninstall.resolve("%PROGRAMDATA%/Studio/Game", prefix: prefix, fileManager: fm)?.path,
                       prefix.appendingPathComponent("drive_c/ProgramData/Studio/Game").path)
    }

    func testNeedsExactlyOneWindowsUser() throws {
        try make(prefix.appendingPathComponent("drive_c/users/Public", isDirectory: true))
        try make(prefix.appendingPathComponent("drive_c/users/a", isDirectory: true))
        try make(prefix.appendingPathComponent("drive_c/users/b", isDirectory: true))
        XCTAssertNil(SteamUninstall.resolve("%APPDATA%/SEGA/P5R", prefix: prefix, fileManager: fm))
    }

    func testRefusesInstallFoldersThatLeaveCommon() {
        for name in ["", ".", "..", "../Steam", "a/b", #"a\b"#] {
            XCTAssertThrowsError(
                try SteamUninstall.plan(for: app(installDirectory: name), steamDirectory: steam, prefix: prefix), name
            ) { error in
                XCTAssertEqual(error as? SteamUninstallError, .unsafeInstallDirectory(name))
            }
        }
    }

    func testGameWithoutScriptOrSaves() throws {
        try write("demo", to: steam.appendingPathComponent("steamapps/common/Demo/demo.exe"))
        try write("manifest", to: steam.appendingPathComponent("steamapps/appmanifest_1687950.acf"))
        let plan = try SteamUninstall.plan(for: app(installDirectory: "Demo"), steamDirectory: steam, prefix: prefix)
        XCTAssertEqual(plan.gameItems.count, 2)
        XCTAssertEqual(plan.saveFolders, [])
    }
}
