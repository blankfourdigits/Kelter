import Foundation
import XCTest
import KelterCore
@testable import KelterWine

final class WineVariantTests: XCTestCase {
    private var root: URL!
    private var paths: AppPaths!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterVariant-\(UUID().uuidString)", isDirectory: true)
        paths = AppPaths(root: root)
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func wineConfig() -> RuntimeConfig.Wine {
        RuntimeConfig.Wine(
            name: "Test",
            version: "11.21",
            url: URL(string: "https://example.invalid/wine.tar.xz")!,
            sha256: nil,
            archiveRoot: "Wine.app",
            binDirectory: "bin",
            libDirectory: "lib",
            supportsESync: false,
            supportsMSync: false
        )
    }

    private func layer() -> RuntimeConfig.GraphicsLayer {
        RuntimeConfig.GraphicsLayer(
            id: "dxmt",
            name: "DXMT",
            version: "0.80",
            url: URL(string: "https://example.invalid/dxmt.tar.gz")!,
            sha256: nil,
            archiveRoot: "v0.80",
            libraryTarget: "wine",
            prefixLibraries: [
                "x86_64-windows": "drive_c/windows/system32",
                "i386-windows": "drive_c/windows/syswow64"
            ]
        )
    }

    private func layerWithWineFiles(wineVersion: String = "11.21") -> RuntimeConfig.GraphicsLayer {
        var layer = layer()
        layer.wineFiles = RuntimeConfig.WineFiles(
            name: "Mac-Treiber",
            version: "1",
            wineVersion: wineVersion,
            files: ["x86_64-unix/winemac.so"],
            buildScript: "Tools/wine-dxmt/build.sh"
        )
        return layer
    }

    private var wineFilesSource: URL {
        paths.wineFilesDirectory(layerID: "dxmt", wineVersion: "11.21", version: "1")
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func testExpectedLocation() {
        let variant = WineVariantInstaller.expected(paths: paths, wine: wineConfig(), layer: layer())
        XCTAssertEqual(
            variant.wine.path,
            root.path + "/Runtimes/wine-variants/11.21+dxmt-0.80/Wine.app/bin/wine"
        )
        XCTAssertEqual(variant.libDirectory.path, root.path + "/Runtimes/wine-variants/11.21+dxmt-0.80/Wine.app/lib")
    }

    func testWineFilesRevisionGetsItsOwnCopy() {
        let variant = WineVariantInstaller.variantDirectory(paths: paths, wine: wineConfig(), layer: layerWithWineFiles())
        XCTAssertEqual(variant.lastPathComponent, "11.21+dxmt-0.80+wine-1")
        XCTAssertEqual(wineFilesSource.path, root.path + "/Runtimes/wine-files/dxmt/11.21-1")
    }

    func testLayerWithoutWineFilesNeedsNothing() throws {
        XCTAssertNil(try WineVariantInstaller.checkWineFiles(layer: layer(), wine: wineConfig(), paths: paths))
    }

    func testMissingWineFilesNameTheBuildScript() {
        XCTAssertThrowsError(
            try WineVariantInstaller.checkWineFiles(layer: layerWithWineFiles(), wine: wineConfig(), paths: paths)
        ) { error in
            XCTAssertEqual(
                error as? WineFilesError,
                .missing(name: "Mac-Treiber", layer: "DXMT", files: ["x86_64-unix/winemac.so"],
                         buildScript: "Tools/wine-dxmt/build.sh")
            )
            XCTAssertTrue(error.localizedDescription.contains("bash Tools/wine-dxmt/build.sh"))
        }
    }

    func testWineFilesForAnotherWineAreRefused() throws {
        // Even if the file is there: a driver for another Wine must not be used.
        try write("driver", to: wineFilesSource.appendingPathComponent("x86_64-unix/winemac.so"))
        XCTAssertThrowsError(
            try WineVariantInstaller.checkWineFiles(
                layer: layerWithWineFiles(wineVersion: "11.20"), wine: wineConfig(), paths: paths)
        ) { error in
            XCTAssertEqual(
                error as? WineFilesError,
                .wrongWineVersion(name: "Mac-Treiber", expected: "11.20", installed: "11.21")
            )
        }
    }

    func testWineFilesReplaceWinesOwn() throws {
        try write("patched driver", to: wineFilesSource.appendingPathComponent("x86_64-unix/winemac.so"))
        let libraries = root.appendingPathComponent("copy/lib/wine", isDirectory: true)
        try write("gcenx driver", to: libraries.appendingPathComponent("x86_64-unix/winemac.so"))
        try write("ntdll", to: libraries.appendingPathComponent("x86_64-unix/ntdll.so"))

        let count = try WineVariantInstaller.installWineFiles(
            layer: layerWithWineFiles(), wine: wineConfig(), paths: paths, into: libraries, fileManager: .default)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(try read(libraries.appendingPathComponent("x86_64-unix/winemac.so")), "patched driver")
        XCTAssertEqual(try read(libraries.appendingPathComponent("x86_64-unix/ntdll.so")), "ntdll")
        // The build output stays for the next copy.
        XCTAssertEqual(try read(wineFilesSource.appendingPathComponent("x86_64-unix/winemac.so")), "patched driver")
    }

    func testLocateNeedsMarkerAndExecutable() throws {
        XCTAssertNil(WineVariantInstaller.locate(paths: paths, wine: wineConfig(), layer: layer()))

        let variant = WineVariantInstaller.expected(paths: paths, wine: wineConfig(), layer: layer())
        try write("#!/bin/sh\n", to: variant.wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: variant.wine.path)
        XCTAssertNil(
            WineVariantInstaller.locate(paths: paths, wine: wineConfig(), layer: layer()),
            "a copy without the completion marker is half-built"
        )

        let directory = WineVariantInstaller.variantDirectory(paths: paths, wine: wineConfig(), layer: layer())
        try write("", to: directory.appendingPathComponent(WineVariantInstaller.markerFileName))
        XCTAssertEqual(WineVariantInstaller.locate(paths: paths, wine: wineConfig(), layer: layer()), variant)
    }

    func testOverlayReplacesAndAddsFiles() throws {
        let source = root.appendingPathComponent("layer", isDirectory: true)
        let target = root.appendingPathComponent("wine/lib/wine", isDirectory: true)
        try write("dxmt d3d11", to: source.appendingPathComponent("x86_64-windows/d3d11.dll"))
        try write("winemetal", to: source.appendingPathComponent("x86_64-unix/winemetal.so"))
        try write("ignored", to: source.appendingPathComponent("x86_64-windows/.DS_Store"))
        try write("wine d3d11", to: target.appendingPathComponent("x86_64-windows/d3d11.dll"))
        try write("wine d3d9", to: target.appendingPathComponent("x86_64-windows/d3d9.dll"))

        let count = try WineVariantInstaller.overlay(from: source, onto: target, fileManager: .default)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(try read(target.appendingPathComponent("x86_64-windows/d3d11.dll")), "dxmt d3d11")
        XCTAssertEqual(try read(target.appendingPathComponent("x86_64-unix/winemetal.so")), "winemetal")
        // Files the layer does not ship stay as they are.
        XCTAssertEqual(try read(target.appendingPathComponent("x86_64-windows/d3d9.dll")), "wine d3d9")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("x86_64-windows/.DS_Store").path))
        // The layer's own files are untouched.
        XCTAssertEqual(try read(source.appendingPathComponent("x86_64-windows/d3d11.dll")), "dxmt d3d11")
    }

    func testPrefixLibrariesAddOnlyWhatIsMissing() throws {
        let files = paths.graphicsLayerDirectory(id: "dxmt", version: "0.80")
            .appendingPathComponent("v0.80", isDirectory: true)
        try write("dxmt d3d11", to: files.appendingPathComponent("x86_64-windows/d3d11.dll"))
        try write("winemetal 64", to: files.appendingPathComponent("x86_64-windows/winemetal.dll"))
        try write("winemetal 32", to: files.appendingPathComponent("i386-windows/winemetal.dll"))
        try write("unix", to: files.appendingPathComponent("x86_64-unix/winemetal.so"))

        let prefix = root.appendingPathComponent("prefix", isDirectory: true)
        // Not set up by Wine yet: nothing to do, no error.
        XCTAssertEqual(try WineVariantInstaller.installPrefixLibraries(layer: layer(), paths: paths, prefix: prefix), [])

        let system32 = prefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let syswow64 = prefix.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)
        try write("wine d3d11", to: system32.appendingPathComponent("d3d11.dll"))
        try FileManager.default.createDirectory(at: syswow64, withIntermediateDirectories: true)

        let added = try WineVariantInstaller.installPrefixLibraries(layer: layer(), paths: paths, prefix: prefix)

        XCTAssertEqual(added, [
            "drive_c/windows/syswow64/winemetal.dll",
            "drive_c/windows/system32/winemetal.dll"
        ])
        XCTAssertEqual(try read(system32.appendingPathComponent("winemetal.dll")), "winemetal 64")
        XCTAssertEqual(try read(syswow64.appendingPathComponent("winemetal.dll")), "winemetal 32")
        // What the bottle already has stays as Wine put it there.
        XCTAssertEqual(try read(system32.appendingPathComponent("d3d11.dll")), "wine d3d11")
        // A second run finds nothing left to add.
        XCTAssertEqual(try WineVariantInstaller.installPrefixLibraries(layer: layer(), paths: paths, prefix: prefix), [])
    }

    func testRunnerPicksVariantByGraphicsChoice() {
        let plain = WineInstallation.expected(paths: paths, config: wineConfig())
        let dxmt = WineVariantInstaller.expected(paths: paths, wine: wineConfig(), layer: layer())
        let runner = WineRunner(
            installation: plain,
            config: wineConfig(),
            variants: [.dxmt: dxmt],
            log: LogFile(url: paths.logFile)
        )

        var settings = BottleSettings()
        XCTAssertEqual(runner.installation(for: settings), plain)

        settings.graphicsBackend = .dxmt
        XCTAssertEqual(runner.installation(for: settings), dxmt)

        // A choice without its own copy falls back to the plain Wine.
        settings.graphicsBackend = .dxvk
        XCTAssertEqual(runner.installation(for: settings), plain)
    }
}
