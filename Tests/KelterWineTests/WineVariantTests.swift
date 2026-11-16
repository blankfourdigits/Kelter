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

    private func patches(wineVersion: String = "11.21", url: URL? = nil) -> RuntimeConfig.WinePatches {
        RuntimeConfig.WinePatches(
            name: "Wine-Anpassungen",
            version: "2",
            wineVersion: wineVersion,
            buildScript: "Tools/wine-patches/build.sh",
            url: url,
            sha256: url == nil ? nil : String(repeating: "a", count: 64)
        )
    }

    private let filesURL = URL(string: "https://example.invalid/kelter-wine-files-11.21-2.tar.xz")!

    private func layerWithWineFiles() -> RuntimeConfig.GraphicsLayer {
        var layer = layer()
        layer.wineFiles = ["x86_64-unix/winemac.so"]
        return layer
    }

    private var wineFilesSource: URL {
        paths.wineFilesDirectory(wineVersion: "11.21", version: "2")
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func testExpectedLocation() {
        let variant = WineVariantInstaller.expected(paths: paths, wine: wineConfig(), layer: layer(), patches: nil)
        XCTAssertEqual(
            variant.wine.path,
            root.path + "/Runtimes/wine-variants/11.21+dxmt-0.80/Wine.app/bin/wine"
        )
        XCTAssertEqual(variant.libDirectory.path, root.path + "/Runtimes/wine-variants/11.21+dxmt-0.80/Wine.app/lib")
    }

    func testWineFilesRevisionGetsItsOwnCopy() {
        let variant = WineVariantInstaller.variantDirectory(
            paths: paths, wine: wineConfig(), layer: layerWithWineFiles(), patches: patches())
        XCTAssertEqual(variant.lastPathComponent, "11.21+dxmt-0.80+wine-2")
        XCTAssertEqual(wineFilesSource.path, root.path + "/Runtimes/wine-files/11.21-2")
        // A layer that needs none of Kelter's Wine files keeps its name.
        XCTAssertEqual(
            WineVariantInstaller.variantDirectory(paths: paths, wine: wineConfig(), layer: layer(), patches: patches())
                .lastPathComponent,
            "11.21+dxmt-0.80"
        )
    }

    func testLayerWithoutWineFilesNeedsNothing() throws {
        XCTAssertNil(try WineVariantInstaller.checkWineFiles(
            layer: layer(), patches: nil, wine: wineConfig(), paths: paths))
    }

    func testWineFilesWithoutPatchesSectionAreAnError() {
        XCTAssertThrowsError(try WineVariantInstaller.checkWineFiles(
            layer: layerWithWineFiles(), patches: nil, wine: wineConfig(), paths: paths)
        ) { error in
            XCTAssertEqual(error as? WineFilesError, .notConfigured(layer: "DXMT"))
        }
    }

    func testMissingWineFilesNameTheBuildScript() {
        XCTAssertThrowsError(try WineVariantInstaller.checkWineFiles(
            layer: layerWithWineFiles(), patches: patches(), wine: wineConfig(), paths: paths)
        ) { error in
            XCTAssertEqual(
                error as? WineFilesError,
                .missing(name: "Wine-Anpassungen", layer: "DXMT", files: ["x86_64-unix/winemac.so"],
                         buildScript: "Tools/wine-patches/build.sh")
            )
            XCTAssertTrue(error.localizedDescription.contains("bash Tools/wine-patches/build.sh"))
        }
    }

    func testPlanWithoutWineFilesNeedsNothing() throws {
        XCTAssertEqual(
            try WineVariantInstaller.planWineFiles(
                layer: layer(), patches: patches(url: filesURL), wine: wineConfig(), paths: paths),
            .notNeeded)
    }

    func testPlanDownloadsMissingFilesIfConfigured() throws {
        XCTAssertEqual(
            try WineVariantInstaller.planWineFiles(
                layer: layerWithWineFiles(), patches: patches(url: filesURL), wine: wineConfig(), paths: paths),
            .download(filesURL, sha256: String(repeating: "a", count: 64)))
    }

    func testPlanPrefersFilesThatAreThere() throws {
        // Built locally (or downloaded before): no download.
        try write("driver", to: wineFilesSource.appendingPathComponent("x86_64-unix/winemac.so"))
        XCTAssertEqual(
            try WineVariantInstaller.planWineFiles(
                layer: layerWithWineFiles(), patches: patches(url: filesURL), wine: wineConfig(), paths: paths),
            .ready)
    }

    func testPlanWithoutDownloadNamesTheBuildScript() {
        XCTAssertThrowsError(try WineVariantInstaller.planWineFiles(
            layer: layerWithWineFiles(), patches: patches(), wine: wineConfig(), paths: paths)
        ) { error in
            guard case .missing? = error as? WineFilesError else {
                return XCTFail("expected .missing, got \(error)")
            }
        }
    }

    func testPlanNeverDownloadsForAnotherWine() {
        XCTAssertThrowsError(try WineVariantInstaller.planWineFiles(
            layer: layerWithWineFiles(), patches: patches(wineVersion: "11.20", url: filesURL),
            wine: wineConfig(), paths: paths)
        ) { error in
            guard case .wrongWineVersion? = error as? WineFilesError else {
                return XCTFail("expected .wrongWineVersion, got \(error)")
            }
        }
    }

    func testWineFilesForAnotherWineAreRefused() throws {
        // Even if the file is there: a driver for another Wine must not be used.
        try write("driver", to: wineFilesSource.appendingPathComponent("x86_64-unix/winemac.so"))
        XCTAssertThrowsError(try WineVariantInstaller.checkWineFiles(
            layer: layerWithWineFiles(), patches: patches(wineVersion: "11.20"), wine: wineConfig(), paths: paths)
        ) { error in
            XCTAssertEqual(
                error as? WineFilesError,
                .wrongWineVersion(name: "Wine-Anpassungen", expected: "11.20", installed: "11.21")
            )
        }
    }

    func testWineFilesReplaceWinesOwn() throws {
        var layer = layerWithWineFiles()
        layer.wineFiles = ["x86_64-unix/winemac.so", "x86_64-windows/ntdll.dll"]
        try write("patched driver", to: wineFilesSource.appendingPathComponent("x86_64-unix/winemac.so"))
        try write("patched ntdll", to: wineFilesSource.appendingPathComponent("x86_64-windows/ntdll.dll"))
        let libraries = root.appendingPathComponent("copy/lib/wine", isDirectory: true)
        try write("gcenx driver", to: libraries.appendingPathComponent("x86_64-unix/winemac.so"))
        try write("gcenx ntdll", to: libraries.appendingPathComponent("x86_64-windows/ntdll.dll"))
        try write("win32u", to: libraries.appendingPathComponent("x86_64-unix/win32u.so"))

        let count = try WineVariantInstaller.installWineFiles(
            layer: layer, patches: patches(), wine: wineConfig(), paths: paths,
            into: libraries, fileManager: .default)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(try read(libraries.appendingPathComponent("x86_64-unix/winemac.so")), "patched driver")
        XCTAssertEqual(try read(libraries.appendingPathComponent("x86_64-windows/ntdll.dll")), "patched ntdll")
        XCTAssertEqual(try read(libraries.appendingPathComponent("x86_64-unix/win32u.so")), "win32u")
        // The build output stays for the next copy.
        XCTAssertEqual(try read(wineFilesSource.appendingPathComponent("x86_64-unix/winemac.so")), "patched driver")
    }

    /// A package laid out like Apple's: a framework with version links and
    /// libraries that link to one shared library.
    private func makeFrameworkPackage(at lib: URL) throws {
        let fm = FileManager.default
        let framework = lib.appendingPathComponent("external/D3DMetal.framework")
        try write("binary", to: framework.appendingPathComponent("Versions/A/D3DMetal"))
        try write("plist", to: framework.appendingPathComponent("Versions/A/Resources/version.plist"))
        try fm.createSymbolicLink(atPath: framework.appendingPathComponent("Versions/Current").path,
                                  withDestinationPath: "A")
        try fm.createSymbolicLink(atPath: framework.appendingPathComponent("D3DMetal").path,
                                  withDestinationPath: "Versions/Current/D3DMetal")
        try fm.createSymbolicLink(atPath: framework.appendingPathComponent("Resources").path,
                                  withDestinationPath: "Versions/Current/Resources")
        try write("shared", to: lib.appendingPathComponent("external/libd3dshared.dylib"))
        try write("pe d3d12", to: lib.appendingPathComponent("wine/x86_64-windows/d3d12.dll"))
        try write("old wine", to: lib.appendingPathComponent("wine/x86_64-windows/kernel32.dll"))
        try fm.createDirectory(at: lib.appendingPathComponent("wine/x86_64-unix"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: lib.appendingPathComponent("wine/x86_64-unix/d3d12.so").path,
                                  withDestinationPath: "../../external/libd3dshared.dylib")
    }

    private func linkDestination(_ url: URL) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    }

    func testSelectionKeepsOnlyIncludedPathsAndLinks() throws {
        let package = root.appendingPathComponent("package/lib", isDirectory: true)
        try makeFrameworkPackage(at: package)
        let target = root.appendingPathComponent("selection", isDirectory: true)

        try WineVariantInstaller.copySelection(
            ["external/D3DMetal.framework", "external/libd3dshared.dylib",
             "wine/x86_64-windows/d3d12.dll", "wine/x86_64-unix/d3d12.so"],
            from: package, to: target, layerName: "D3DMetal", fileManager: .default)

        XCTAssertEqual(linkDestination(target.appendingPathComponent("external/D3DMetal.framework/Versions/Current")), "A")
        XCTAssertEqual(try read(target.appendingPathComponent("external/D3DMetal.framework/D3DMetal")), "binary")
        XCTAssertEqual(linkDestination(target.appendingPathComponent("wine/x86_64-unix/d3d12.so")),
                       "../../external/libd3dshared.dylib")
        XCTAssertEqual(try read(target.appendingPathComponent("wine/x86_64-unix/d3d12.so")), "shared")
        // The package's own Wine stays behind.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: target.appendingPathComponent("wine/x86_64-windows/kernel32.dll").path))
    }

    func testSelectionNamesAMissingFile() throws {
        let package = root.appendingPathComponent("package/lib", isDirectory: true)
        try makeFrameworkPackage(at: package)
        XCTAssertThrowsError(try WineVariantInstaller.copySelection(
            ["wine/x86_64-windows/dxgi.dll"], from: package,
            to: root.appendingPathComponent("selection"), layerName: "D3DMetal", fileManager: .default)
        ) { error in
            XCTAssertEqual(error as? LayerSourceError, .fileMissing(layer: "D3DMetal", path: "wine/x86_64-windows/dxgi.dll"))
        }
    }

    func testOverlayKeepsFrameworkLinks() throws {
        let source = root.appendingPathComponent("layer", isDirectory: true)
        try makeFrameworkPackage(at: source)
        let target = root.appendingPathComponent("wine/lib", isDirectory: true)
        try write("wine d3d12", to: target.appendingPathComponent("wine/x86_64-unix/d3d12.so"))

        _ = try WineVariantInstaller.overlay(from: source, onto: target, fileManager: .default)

        let framework = target.appendingPathComponent("external/D3DMetal.framework")
        XCTAssertEqual(linkDestination(framework.appendingPathComponent("Versions/Current")), "A")
        XCTAssertEqual(linkDestination(framework.appendingPathComponent("Resources")), "Versions/Current/Resources")
        XCTAssertEqual(try read(framework.appendingPathComponent("Resources/version.plist")), "plist")
        // Wine's own library is replaced by the link to the layer's.
        XCTAssertEqual(try read(target.appendingPathComponent("wine/x86_64-unix/d3d12.so")), "shared")
    }

    func testLayerFilesNeedTheirMarker() throws {
        var layer = layer()
        layer.include = ["external/libd3dshared.dylib"]
        XCTAssertFalse(WineVariantInstaller.hasLayerFiles(paths: paths, layer: layer))
        // With an include list the files lie directly in the layer's folder.
        let directory = try WineVariantInstaller.layerFilesDirectory(paths: paths, layer: layer)
        XCTAssertEqual(directory, paths.graphicsLayerDirectory(id: "dxmt", version: "0.80"))
        try write("", to: directory.appendingPathComponent(WineVariantInstaller.layerMarkerFileName))
        XCTAssertTrue(WineVariantInstaller.hasLayerFiles(paths: paths, layer: layer))
        // Without, below the archive root.
        XCTAssertEqual(try WineVariantInstaller.layerFilesDirectory(paths: paths, layer: self.layer()).lastPathComponent,
                       "v0.80")
    }

    func testLocateNeedsMarkerAndExecutable() throws {
        XCTAssertNil(WineVariantInstaller.locate(paths: paths, wine: wineConfig(), layer: layer(), patches: nil))

        let variant = WineVariantInstaller.expected(paths: paths, wine: wineConfig(), layer: layer(), patches: nil)
        try write("#!/bin/sh\n", to: variant.wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: variant.wine.path)
        XCTAssertNil(
            WineVariantInstaller.locate(paths: paths, wine: wineConfig(), layer: layer(), patches: nil),
            "a copy without the completion marker is half-built"
        )

        let directory = WineVariantInstaller.variantDirectory(paths: paths, wine: wineConfig(), layer: layer(), patches: nil)
        try write("", to: directory.appendingPathComponent(WineVariantInstaller.markerFileName))
        XCTAssertEqual(WineVariantInstaller.locate(paths: paths, wine: wineConfig(), layer: layer(), patches: nil), variant)
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
        let dxmt = WineVariantInstaller.expected(paths: paths, wine: wineConfig(), layer: layer(), patches: nil)
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
