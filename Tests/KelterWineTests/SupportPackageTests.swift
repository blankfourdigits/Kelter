import Foundation
import XCTest
import KelterCore
@testable import KelterWine

final class SupportPackageTests: XCTestCase {
    private var root: URL!
    private var paths: AppPaths!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterSupport-\(UUID().uuidString)", isDirectory: true)
        paths = AppPaths(root: root)
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func supportConfig() -> RuntimeConfig.Support {
        RuntimeConfig.Support(
            name: "Test Support",
            version: "1.0",
            url: URL(string: "https://example.invalid/support.tar.xz")!,
            sha256: nil,
            archiveRoot: "Support.app",
            libraryPaths: ["Contents/Frameworks", "Contents/Frameworks/GStreamer/Libraries"],
            gstreamerPluginPath: "Contents/Frameworks/GStreamer/Libraries/gstreamer-1.0",
            vulkanDriverFile: "Contents/Resources/vulkan/icd.d/MoltenVK_icd.json",
            renderers: [
                .init(id: "d9vk", variable: "WINEDLLPATH_D9VK", path: "Contents/Frameworks/renderer/d9vk/wine"),
                .init(id: "dxmt", variable: "WINEDLLPATH_DXMT", path: "Contents/Frameworks/renderer/dxmt/wine"),
                .init(id: "dxvk", variable: "WINEDLLPATH_DXVK", path: "Contents/Frameworks/renderer/dxvk/wine"),
            ],
            removeAfterInstall: ["Contents/Frameworks/renderer/d3dmetal"],
            environment: ["ROSETTA_ADVERTISE_AVX": "1"]
        )
    }

    private func wineConfig() -> RuntimeConfig.Wine {
        RuntimeConfig.Wine(
            name: "Test",
            version: "1.0",
            url: URL(string: "https://example.invalid/wine.tar.xz")!,
            sha256: nil,
            archiveRoot: "wine.bundle",
            binDirectory: "bin",
            libDirectory: "lib",
            supportsESync: false,
            supportsMSync: true
        )
    }

    private var packageRoot: String {
        root.path + "/Runtimes/support/1.0/Support.app"
    }

    // MARK: Locations

    func testExpectedLocations() {
        let support = SupportInstallation.expected(paths: paths, config: supportConfig())

        XCTAssertEqual(support.root.path, packageRoot)
        XCTAssertEqual(
            support.libraryDirectories.map(\.path),
            [packageRoot + "/Contents/Frameworks", packageRoot + "/Contents/Frameworks/GStreamer/Libraries"]
        )
        XCTAssertEqual(
            support.vulkanDriverFile?.path,
            packageRoot + "/Contents/Resources/vulkan/icd.d/MoltenVK_icd.json"
        )
        XCTAssertEqual(support.renderer(id: "dxmt")?.variable, "WINEDLLPATH_DXMT")
        XCTAssertEqual(
            support.renderer(id: "dxmt")?.directory.path,
            packageRoot + "/Contents/Frameworks/renderer/dxmt/wine"
        )
        XCTAssertNil(support.renderer(id: "d3dmetal"))
    }

    func testLocateNeedsEveryLibraryFolder() throws {
        let config = supportConfig()
        XCTAssertNil(SupportInstallation.locate(paths: paths, config: config))

        let expected = SupportInstallation.expected(paths: paths, config: config)
        try FileManager.default.createDirectory(at: expected.libraryDirectories[0], withIntermediateDirectories: true)
        XCTAssertNil(SupportInstallation.locate(paths: paths, config: config), "second library folder is missing")

        try FileManager.default.createDirectory(at: expected.libraryDirectories[1], withIntermediateDirectories: true)
        XCTAssertEqual(SupportInstallation.locate(paths: paths, config: config), expected)
    }

    // MARK: Environment

    private func makeEnvironment(_ backend: GraphicsBackendKind, base: [String: String] = [:]) -> [String: String] {
        var settings = BottleSettings()
        settings.graphicsBackend = backend
        return WineEnvironment.make(
            base: base,
            prefix: URL(fileURLWithPath: "/tmp/prefix"),
            settings: settings,
            wine: wineConfig(),
            support: SupportInstallation.expected(paths: paths, config: supportConfig())
        )
    }

    func testSupportLibrariesAreAlwaysSet() {
        let environment = makeEnvironment(.wined3d, base: ["DYLD_FALLBACK_LIBRARY_PATH": "/injected"])

        XCTAssertEqual(
            environment["DYLD_FALLBACK_LIBRARY_PATH"],
            packageRoot + "/Contents/Frameworks:" + packageRoot + "/Contents/Frameworks/GStreamer/Libraries:/usr/lib"
        )
        XCTAssertEqual(
            environment["GST_PLUGIN_PATH"],
            packageRoot + "/Contents/Frameworks/GStreamer/Libraries/gstreamer-1.0"
        )
        XCTAssertEqual(
            environment["VK_DRIVER_FILES"],
            packageRoot + "/Contents/Resources/vulkan/icd.d/MoltenVK_icd.json"
        )
        XCTAssertEqual(environment["VK_ICD_FILENAMES"], environment["VK_DRIVER_FILES"])
        XCTAssertEqual(environment["ROSETTA_ADVERTISE_AVX"], "1")
    }

    func testBuiltInGraphicsSwitchesNoRendererOn() {
        let environment = makeEnvironment(.wined3d)
        XCTAssertNil(environment["WINEDLLPATH_D9VK"])
        XCTAssertNil(environment["WINEDLLPATH_DXMT"])
        XCTAssertNil(environment["WINEDLLPATH_DXVK"])
    }

    func testDXMTAlsoSwitchesD9VKOn() {
        let environment = makeEnvironment(.dxmt)
        XCTAssertEqual(environment["WINEDLLPATH_D9VK"], packageRoot + "/Contents/Frameworks/renderer/d9vk/wine")
        XCTAssertEqual(environment["WINEDLLPATH_DXMT"], packageRoot + "/Contents/Frameworks/renderer/dxmt/wine")
        XCTAssertNil(environment["WINEDLLPATH_DXVK"])
    }

    func testDXVKAlsoSwitchesD9VKOn() {
        let environment = makeEnvironment(.dxvk)
        XCTAssertEqual(environment["WINEDLLPATH_D9VK"], packageRoot + "/Contents/Frameworks/renderer/d9vk/wine")
        XCTAssertEqual(environment["WINEDLLPATH_DXVK"], packageRoot + "/Contents/Frameworks/renderer/dxvk/wine")
        XCTAssertNil(environment["WINEDLLPATH_DXMT"])
    }

    func testMissingRendererIsLeftOut() {
        // D3DMetal is not part of the package: the others it needs still work.
        let environment = makeEnvironment(.d3dmetal)
        XCTAssertNotNil(environment["WINEDLLPATH_D9VK"])
        XCTAssertNotNil(environment["WINEDLLPATH_DXMT"])
        XCTAssertNil(environment["WINEDLLPATH_D3DMETAL"])
    }

    func testWithoutSupportPackageNothingIsAdded() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxmt
        let environment = WineEnvironment.make(
            base: [:],
            prefix: URL(fileURLWithPath: "/tmp/prefix"),
            settings: settings,
            wine: wineConfig()
        )
        XCTAssertNil(environment["DYLD_FALLBACK_LIBRARY_PATH"])
        XCTAssertNil(environment["VK_DRIVER_FILES"])
        XCTAssertNil(environment["WINEDLLPATH_DXMT"])
    }

    func testMSyncOnlyWhenSwitchedOn() {
        var settings = BottleSettings()
        let off = WineEnvironment.make(base: [:], prefix: URL(fileURLWithPath: "/tmp/p"), settings: settings, wine: wineConfig())
        XCTAssertNil(off["WINEMSYNC"])

        settings.msync = true
        let on = WineEnvironment.make(base: [:], prefix: URL(fileURLWithPath: "/tmp/p"), settings: settings, wine: wineConfig())
        XCTAssertEqual(on["WINEMSYNC"], "1")
    }

    // MARK: Paths from the configuration

    func testSafeRelativePathAcceptsOrdinaryPaths() throws {
        XCTAssertEqual(try ArchiveInstaller.safeRelativePath("Contents/Frameworks/renderer/d3dmetal"), "Contents/Frameworks/renderer/d3dmetal")
        XCTAssertEqual(try ArchiveInstaller.safeRelativePath("a//b/"), "a/b")
        XCTAssertEqual(try ArchiveInstaller.safeRelativePath("Wine Staging.app"), "Wine Staging.app")
    }

    func testSafeRelativePathRejectsEscapes() {
        for path in ["/etc/passwd", "../outside", "a/../../b", "", "/", ".", "a/./b"] {
            XCTAssertThrowsError(try ArchiveInstaller.safeRelativePath(path), path) { error in
                XCTAssertEqual(error as? WineInstallError, .unsafePath(path))
            }
        }
    }
}
