import Foundation
import XCTest
import KelterCore
@testable import KelterWine

final class WineEnvironmentTests: XCTestCase {
    private let prefix = URL(fileURLWithPath: "/tmp/Kelter Test/prefix")

    private func wineConfig(esync: Bool = false, msync: Bool = false) -> RuntimeConfig.Wine {
        RuntimeConfig.Wine(
            name: "Test",
            version: "1.0",
            url: URL(string: "https://example.invalid/wine.tar.xz")!,
            sha256: nil,
            archiveRoot: "Wine.app",
            binDirectory: "bin",
            libDirectory: "lib",
            supportsESync: esync,
            supportsMSync: msync
        )
    }

    func testSetsPrefixAndKeepsInheritedVariables() {
        let environment = WineEnvironment.make(
            base: ["HOME": "/Users/test", "PATH": "/usr/bin"],
            prefix: prefix,
            settings: BottleSettings(),
            wine: wineConfig()
        )
        XCTAssertEqual(environment["WINEPREFIX"], "/tmp/Kelter Test/prefix")
        XCTAssertEqual(environment["HOME"], "/Users/test")
        XCTAssertEqual(environment["PATH"], "/usr/bin")
        XCTAssertEqual(environment["WINEDEBUG"], "fixme-all")
    }

    func testDropsInjectedDyldVariables() {
        let environment = WineEnvironment.make(
            base: [
                "DYLD_INSERT_LIBRARIES": "/some/arm64.dylib",
                "__XPC_DYLD_LIBRARY_PATH": "/build",
                "HOME": "/Users/test",
            ],
            prefix: prefix,
            settings: BottleSettings(),
            wine: wineConfig()
        )
        XCTAssertNil(environment["DYLD_INSERT_LIBRARIES"])
        XCTAssertNil(environment["__XPC_DYLD_LIBRARY_PATH"])
        XCTAssertEqual(environment["HOME"], "/Users/test")
    }

    func testInheritedWineDebugIsKept() {
        let environment = WineEnvironment.make(
            base: ["WINEDEBUG": "+loaddll"],
            prefix: prefix,
            settings: BottleSettings(),
            wine: wineConfig()
        )
        XCTAssertEqual(environment["WINEDEBUG"], "+loaddll")
    }

    func testVerboseLoggingReplacesWineDebug() {
        var settings = BottleSettings()
        settings.verboseLogging = true
        let environment = WineEnvironment.make(
            base: ["WINEDEBUG": "-all"],
            prefix: prefix,
            settings: settings,
            wine: wineConfig()
        )
        XCTAssertEqual(environment["WINEDEBUG"], "+timestamp,+pid,+loaddll,+seh")

        // The bottle's own environment still has the last word.
        settings.environment = ["WINEDEBUG": "+d3d"]
        let overridden = WineEnvironment.make(base: [:], prefix: prefix, settings: settings, wine: wineConfig())
        XCTAssertEqual(overridden["WINEDEBUG"], "+d3d")
    }

    func testDllOverridesAreMergedAndSorted() {
        var settings = BottleSettings()
        settings.dllOverrides = ["dxgi": "n", "d3d11": "n,b"]
        let environment = WineEnvironment.make(base: [:], prefix: prefix, settings: settings, wine: wineConfig())
        XCTAssertEqual(environment["WINEDLLOVERRIDES"], "d3d11=n,b;dxgi=n;winemenubuilder.exe=d")
    }

    func testBottleCanOverrideDefaultDllOverride() {
        var settings = BottleSettings()
        settings.dllOverrides = ["winemenubuilder.exe": "b"]
        let environment = WineEnvironment.make(base: [:], prefix: prefix, settings: settings, wine: wineConfig())
        XCTAssertEqual(environment["WINEDLLOVERRIDES"], "winemenubuilder.exe=b")
    }

    func testSyncVariablesOnlyWhenBuildSupportsThem() {
        var settings = BottleSettings()
        settings.esync = true
        settings.msync = true

        let unsupported = WineEnvironment.make(base: [:], prefix: prefix, settings: settings, wine: wineConfig())
        XCTAssertNil(unsupported["WINEESYNC"])
        XCTAssertNil(unsupported["WINEMSYNC"])

        let supported = WineEnvironment.make(
            base: [:],
            prefix: prefix,
            settings: settings,
            wine: wineConfig(esync: true, msync: true)
        )
        XCTAssertEqual(supported["WINEESYNC"], "1")
        XCTAssertEqual(supported["WINEMSYNC"], "1")
    }

    func testMetalHudOnlyWhenEnabled() {
        var settings = BottleSettings()
        let off = WineEnvironment.make(base: [:], prefix: prefix, settings: settings, wine: wineConfig())
        XCTAssertNil(off["MTL_HUD_ENABLED"])

        settings.metalHUD = true
        let on = WineEnvironment.make(base: [:], prefix: prefix, settings: settings, wine: wineConfig())
        XCTAssertEqual(on["MTL_HUD_ENABLED"], "1")
    }

    func testPrecedenceBottleThenExtra() {
        var settings = BottleSettings()
        settings.environment = ["WINEDEBUG": "-all", "CUSTOM": "bottle"]
        let environment = WineEnvironment.make(
            base: ["CUSTOM": "inherited"],
            prefix: prefix,
            settings: settings,
            wine: wineConfig(),
            extra: ["CUSTOM": "extra"]
        )
        XCTAssertEqual(environment["WINEDEBUG"], "-all")
        XCTAssertEqual(environment["CUSTOM"], "extra")
    }

    func testWineInstallationPaths() {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/KelterRoot"))
        let installation = WineInstallation.expected(paths: paths, config: wineConfig())
        XCTAssertEqual(installation.wine.path, "/tmp/KelterRoot/Runtimes/wine/1.0/Wine.app/bin/wine")
        XCTAssertEqual(installation.wineserver.path, "/tmp/KelterRoot/Runtimes/wine/1.0/Wine.app/bin/wineserver")
        // Nothing is installed there.
        XCTAssertNil(WineInstallation.locate(paths: paths, config: wineConfig()))
    }

    func testSha256OfFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("kelter-sha-\(UUID().uuidString).txt")
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(
            try WineInstaller.sha256(of: file),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
