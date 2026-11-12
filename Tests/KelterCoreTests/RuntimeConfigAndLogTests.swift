import Foundation
import XCTest
@testable import KelterCore

final class RuntimeConfigTests: XCTestCase {
    /// `<package root>/Resources/runtimes.json`, found relative to this file.
    private var bundledConfig: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KelterCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Resources/runtimes.json")
    }

    func testBundledConfigIsValid() throws {
        let config = try RuntimeConfig.load(from: bundledConfig)

        XCTAssertEqual(config.schemaVersion, 6)
        XCTAssertFalse(config.wine.version.isEmpty)
        XCTAssertEqual(config.wine.url.scheme, "https")
        // The version becomes a folder name.
        XCTAssertFalse(config.wine.version.contains("/"))
        XCTAssertEqual(config.wine.sha256?.count, 64)
        XCTAssertFalse(config.wine.archiveRoot.isEmpty)
        XCTAssertFalse(config.wine.binDirectory.hasPrefix("/"))
    }

    func testBundledSupportPackageIsValid() throws {
        // The bundled configuration may come without a support package.
        guard let support = try RuntimeConfig.load(from: bundledConfig).support else { return }

        XCTAssertEqual(support.url.scheme, "https")
        XCTAssertEqual(support.sha256?.count, 64)
        XCTAssertFalse(support.archiveRoot.isEmpty)
        XCTAssertFalse(support.libraryPaths.isEmpty)

        // Every path is relative and stays inside the package.
        let paths = support.libraryPaths + support.removeAfterInstall + support.renderers.map(\.path)
            + [support.gstreamerPluginPath, support.vulkanDriverFile].compactMap { $0 }
        for path in paths {
            XCTAssertFalse(path.hasPrefix("/"), path)
            XCTAssertFalse(path.split(separator: "/").contains(".."), path)
        }

        // The renderers every non-built-in graphics choice needs are there,
        // except Apple's D3DMetal, which Kelter does not take from a download.
        let ids = Set(support.renderers.map(\.id))
        XCTAssertEqual(ids.count, support.renderers.count, "renderer ids must be unique")
        XCTAssertTrue(ids.isSuperset(of: ["d9vk", "dxmt", "dxvk"]))
        XCTAssertFalse(ids.contains("d3dmetal"))
        XCTAssertTrue(support.removeAfterInstall.contains { $0.hasSuffix("d3dmetal") })
        for renderer in support.renderers {
            XCTAssertTrue(renderer.variable.hasPrefix("WINEDLLPATH_"), renderer.variable)
        }
    }

    func testConfigWithoutSupportPackageStillLoads() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterConfig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var config = try RuntimeConfig.load(from: bundledConfig)
        config.support = nil
        let file = folder.appendingPathComponent("runtimes.json")
        try JSONEncoder().encode(config).write(to: file)

        XCTAssertNil(try RuntimeConfig.load(from: file).support)
    }

    func testBundledSteamConfigIsValid() throws {
        let steam = try RuntimeConfig.load(from: bundledConfig).steam

        XCTAssertEqual(steam.installerURL.scheme, "https")
        XCTAssertEqual(steam.installerURL.pathExtension, "exe")
        XCTAssertTrue(steam.executablePath.hasSuffix("steam.exe"))
        XCTAssertFalse(steam.executablePath.hasPrefix("/"))
        XCTAssertFalse(steam.argumentPresets.isEmpty)
        // The defaults must be one of the presets, so the UI can show them.
        XCTAssertTrue(steam.argumentPresets.contains { $0.arguments == steam.defaultArguments })
        // Every start parameter is a single word; a space would mean two
        // parameters were written as one.
        for argument in steam.defaultArguments + steam.argumentPresets.flatMap(\.arguments) {
            XCTAssertFalse(argument.contains(" "), argument)
            XCTAssertTrue(argument.hasPrefix("-"), argument)
        }
    }

    func testBundledSteamUIFixIsComplete() throws {
        let uiFix = try RuntimeConfig.load(from: bundledConfig).steam.uiFix

        XCTAssertTrue(uiFix.enabled)
        XCTAssertTrue(uiFix.builtinLibrary.hasSuffix("winmm.dll"))
        XCTAssertFalse(uiFix.browserArguments.isEmpty)
        for argument in uiFix.browserArguments {
            XCTAssertTrue(argument.hasPrefix("--"), argument)
            XCTAssertFalse(argument.contains(" "), argument)
        }

        // The helper library named in the configuration is shipped, and it is
        // a Windows program file ("MZ" header).
        let library = bundledConfig.deletingLastPathComponent().appendingPathComponent(uiFix.library)
        let data = try Data(contentsOf: library)
        XCTAssertEqual(Array(data.prefix(2)), Array("MZ".utf8))
    }

    func testLoadFirstPrefersEarlierCandidate() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterConfig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var custom = try RuntimeConfig.load(from: bundledConfig)
        custom.wine.version = "99.0"
        let override = folder.appendingPathComponent("runtimes.json")
        try JSONEncoder().encode(custom).write(to: override)

        let missing = folder.appendingPathComponent("missing.json")
        let loaded = try RuntimeConfig.loadFirst(candidates: [missing, override, bundledConfig])
        XCTAssertEqual(loaded.config.wine.version, "99.0")
        XCTAssertEqual(loaded.source, override)
    }

    func testBrokenOverrideIsAnErrorNotAFallback() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterConfig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let broken = folder.appendingPathComponent("runtimes.json")
        try Data("{ \"schemaVersion\": 1 }".utf8).write(to: broken)

        XCTAssertThrowsError(try RuntimeConfig.loadFirst(candidates: [broken, bundledConfig])) { error in
            guard case RuntimeConfigError.invalid(let path, _)? = error as? RuntimeConfigError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(path, broken.path)
        }
    }

    func testNoCandidateFound() {
        let missing = URL(fileURLWithPath: "/nonexistent/kelter/runtimes.json")
        XCTAssertThrowsError(try RuntimeConfig.loadFirst(candidates: [missing])) { error in
            XCTAssertEqual(error as? RuntimeConfigError, .notFound([missing.path]))
        }
    }
}

final class AppPathsTests: XCTestCase {
    func testLayout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterPaths-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)

        XCTAssertEqual(paths.wineDirectory(version: "11.21").path, root.path + "/Runtimes/wine/11.21")
        XCTAssertEqual(paths.logFile.path, root.path + "/Logs/kelter.log")

        try paths.ensureDirectories()
        for folder in [paths.bottlesDirectory, paths.runtimesDirectory, paths.downloadsDirectory, paths.logsDirectory] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path), folder.path)
        }
    }

    func testStandardRootIsNamedKelter() {
        XCTAssertEqual(AppPaths.standard().root.lastPathComponent, "Kelter")
    }
}

final class LogFileTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterLog-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("kelter.log")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testAppendAndTail() throws {
        let log = LogFile(url: url)
        try log.prepare()
        let tailer = LogTailer(url: url)

        XCTAssertEqual(tailer.readNew(), "")
        log.append("eins\n")
        log.append("zwei\n")
        XCTAssertEqual(tailer.readNew(), "eins\nzwei\n")
        XCTAssertEqual(tailer.readNew(), "")
        log.append("drei\n")
        XCTAssertEqual(tailer.readNew(), "drei\n")
    }

    func testSkipToEndHidesOldContent() throws {
        let log = LogFile(url: url)
        try log.prepare()
        log.append("alt\n")

        let tailer = LogTailer(url: url)
        tailer.skipToEnd()
        log.append("neu\n")
        XCTAssertEqual(tailer.readNew(), "neu\n")
    }

    func testTailerOnlyReturnsNewestPartOfLargeOutput() throws {
        let log = LogFile(url: url)
        try log.prepare()
        let tailer = LogTailer(url: url)
        log.append(String(repeating: "a", count: 1_000) + "ENDE")
        XCTAssertEqual(tailer.readNew(maxBytes: 4), "ENDE")
        XCTAssertEqual(tailer.readNew(), "")
    }

    func testTailerRestartsAfterTruncation() throws {
        let log = LogFile(url: url)
        try log.prepare()
        let tailer = LogTailer(url: url)
        log.append("eine lange erste Zeile\n")
        _ = tailer.readNew()

        try Data("kurz\n".utf8).write(to: url)
        XCTAssertEqual(tailer.readNew(), "kurz\n")
    }

    func testPrepareRotatesOversizedLog() throws {
        let log = LogFile(url: url)
        try log.prepare()
        log.append(String(repeating: "x", count: 200))

        try log.prepare(maxBytes: 100)

        let rotated = url.appendingPathExtension("1")
        XCTAssertEqual(try Data(contentsOf: rotated).count, 200)
        XCTAssertEqual(try Data(contentsOf: url).count, 0)
    }

    func testChildProcessHandleAppends() throws {
        let log = LogFile(url: url)
        try log.prepare()
        log.append("vorher\n")

        let handle = try log.openForAppending()
        try handle.write(contentsOf: Data("vom Kindprozess\n".utf8))
        try handle.close()
        log.append("nachher\n")

        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8),
            "vorher\nvom Kindprozess\nnachher\n"
        )
    }
}

final class CommandLineArgumentsTests: XCTestCase {
    func testSplitOnWhitespace() {
        XCTAssertEqual(CommandLineArguments.split("-a  -b\t-c"), ["-a", "-b", "-c"])
        XCTAssertEqual(CommandLineArguments.split("   "), [])
        XCTAssertEqual(CommandLineArguments.split(""), [])
    }

    func testQuotesGroupWords() {
        XCTAssertEqual(
            CommandLineArguments.split("-applaunch 620 \"C:\\Program Files\\x\" -silent"),
            ["-applaunch", "620", "C:\\Program Files\\x", "-silent"]
        )
        XCTAssertEqual(CommandLineArguments.split("-name=\"a b\""), ["-name=a b"])
        XCTAssertEqual(CommandLineArguments.split("\"\""), [""])
    }

    func testJoinQuotesOnlyWhereNeeded() {
        XCTAssertEqual(CommandLineArguments.join(["-a", "b c", ""]), "-a \"b c\" \"\"")
        XCTAssertEqual(CommandLineArguments.join([]), "")
    }

    func testRoundTrip() {
        let arguments = ["-cef-in-process-gpu", "C:\\Program Files (x86)\\Steam", "", "-x"]
        XCTAssertEqual(CommandLineArguments.split(CommandLineArguments.join(arguments)), arguments)
    }
}
