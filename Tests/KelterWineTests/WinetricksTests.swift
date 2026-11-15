import Foundation
import XCTest
import KelterCore
@testable import KelterWine

final class WinetricksTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterWinetricks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testVerbsAreCheckedAndSplit() throws {
        XCTAssertEqual(try Winetricks.verbs(fromText: " vcrun2022  corefonts,xact;\nrenderer=gl "),
                       ["vcrun2022", "corefonts", "xact", "renderer=gl"])
        XCTAssertEqual(try Winetricks.verbs(fromText: "   "), [])
        for bad in ["--force", "a;rm -rf", "x$(y)", "ä", "a/b"] {
            XCTAssertThrowsError(try Winetricks.validatedVerbs([bad]), bad)
        }
    }

    func testSearchPathAddsHomebrewOnce() {
        let path = Winetricks.searchPath(base: "/usr/bin:/bin:/opt/homebrew/bin")
        XCTAssertEqual(path.prefix(3), ["/usr/bin", "/bin", "/opt/homebrew/bin"])
        XCTAssertEqual(path.filter { $0 == "/opt/homebrew/bin" }.count, 1)
        XCTAssertTrue(Winetricks.searchPath(base: nil).contains("/usr/local/bin"))
    }

    func testMissingToolsAreFoundInSearchPath() throws {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let tool = bin.appendingPathComponent("cabextract")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        XCTAssertEqual(Winetricks.missingTools(["cabextract", "7z"], searchPath: [bin.path]), ["cabextract", "7z"],
                       "a file that cannot be run does not count")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        XCTAssertEqual(Winetricks.missingTools(["cabextract", "7z"], searchPath: ["/nowhere", bin.path]), ["7z"])
    }

    func testEnvironmentUsesTheBottlesWineTree() {
        let installation = WineInstallation(
            root: URL(fileURLWithPath: "/W"),
            binDirectory: URL(fileURLWithPath: "/W/bin"),
            libDirectory: URL(fileURLWithPath: "/W/lib"),
            version: "11.21"
        )
        let environment = Winetricks.environment(
            installation: installation, cache: URL(fileURLWithPath: "/cache"), searchPath: ["/usr/bin"])
        XCTAssertEqual(environment["WINE"], installation.wine.path)
        XCTAssertEqual(environment["WINESERVER"], installation.wineserver.path)
        XCTAssertEqual(environment["W_CACHE"], "/cache")
        XCTAssertEqual(environment["PATH"], "/W/bin:/usr/bin")
    }

    func testIntactScriptIsNotDownloadedAgain() async throws {
        let paths = AppPaths(root: root)
        try paths.ensureDirectories()
        let script = paths.winetricksScript(version: "1")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho winetricks\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let config = RuntimeConfig.Winetricks(
            version: "1",
            url: URL(string: "https://example.invalid/winetricks")!,   // would fail if fetched
            sha256: try ArchiveInstaller.sha256(of: script),
            verbs: [],
            requiredTools: []
        )
        let result = try await Winetricks.installScript(config, paths: paths, log: LogFile(url: paths.logFile))
        XCTAssertEqual(result, script)
    }

    func testNewerVisualCppIsExplainedNotAFailure() {
        // From a real run in a Steam bottle.
        let output = """
            Executing /W/bin/wine vc_redist.x86.exe /q
            ------------------------------------------------------
            warning: Note: command /W/bin/wine vc_redist.x86.exe /q returned status 102. Aborting.
            ------------------------------------------------------
            """
        XCTAssertEqual(Winetricks.explainFailure(status: 1, output: output),
                       .alreadyNewer(installer: "Visual C++ (vc_redist.x86.exe)"))
        XCTAssertTrue(Winetricks.explainFailure(status: 1, output: output).localizedDescription
            .contains("nichts zu tun"))
        // Other failures stay failures.
        XCTAssertEqual(Winetricks.explainFailure(status: 1, output: "returned status 1. Aborting."), .failed(status: 1))
        XCTAssertEqual(Winetricks.explainFailure(status: 1, output: "setup.exe returned status 102"), .failed(status: 1))
    }
}
