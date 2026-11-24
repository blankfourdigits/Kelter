import Foundation
import XCTest
@testable import KelterCore

final class KelterRemovalTests: XCTestCase {
    private var home: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        home = fm.temporaryDirectory.appendingPathComponent("kelter-removal-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: home)
    }

    private var library: URL { home.appendingPathComponent("Library", isDirectory: true) }
    private var paths: AppPaths { AppPaths(root: library.appendingPathComponent("Application Support/Kelter", isDirectory: true)) }

    private func write(_ relative: String, _ text: String = "x") throws {
        let url = library.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Kelter's files as they are on a Mac, plus things that are not Kelter's.
    private func makeLibrary() throws {
        try write("Application Support/Kelter/Bottles/A/prefix/drive_c/game.exe", String(repeating: "g", count: 10_000))
        try write("Application Support/Kelter/Runtimes/wine/11.21/wine")
        try write("Application Support/Kelter/Logs/kelter.log")
        try write("Application Support/Kelter/runtimes.json")
        try write("Caches/Kelter/wine-patches-build/x")
        try write("HTTPStorages/app.kelter.Kelter/httpstorages.sqlite")
        try write("Preferences/app.kelter.Kelter.plist")
        try write("Preferences/Kelter.plist")
        // Not Kelter's: must stay.
        try write("Application Support/KelterOther/file")
        try write("Preferences/org.winehq.wine.plist")
        try write("Caches/com.example.App/x")
    }

    private func relative(_ urls: [URL]) -> [String] {
        urls.map { String($0.path.dropFirst(library.path.count + 1)) }
    }

    func testRemovesEverythingOfKelter() throws {
        try makeLibrary()
        let plan = KelterRemoval.plan(paths: paths, library: library, bundleIdentifier: "app.kelter.Kelter", keepBottles: false)
        XCTAssertEqual(relative(plan.items), [
            "Application Support/Kelter",
            "Caches/Kelter",
            "Preferences/Kelter.plist",
            "HTTPStorages/app.kelter.Kelter",
            "Preferences/app.kelter.Kelter.plist",
        ])
        XCTAssertNil(plan.keptBottles)
        try KelterRemoval.remove(plan.items)
        XCTAssertFalse(fm.fileExists(atPath: paths.root.path))
        XCTAssertTrue(fm.fileExists(atPath: library.appendingPathComponent("Application Support/KelterOther/file").path))
        XCTAssertTrue(fm.fileExists(atPath: library.appendingPathComponent("Preferences/org.winehq.wine.plist").path))
        XCTAssertTrue(fm.fileExists(atPath: library.appendingPathComponent("Caches/com.example.App/x").path))
    }

    func testCanKeepTheBottles() throws {
        try makeLibrary()
        let plan = KelterRemoval.plan(paths: paths, library: library, bundleIdentifier: "app.kelter.Kelter", keepBottles: true)
        XCTAssertEqual(Array(relative(plan.items).prefix(3)), [
            "Application Support/Kelter/Logs",
            "Application Support/Kelter/Runtimes",
            "Application Support/Kelter/runtimes.json",
        ])
        XCTAssertFalse(plan.items.contains(paths.root))
        XCTAssertEqual(plan.keptBottles, paths.bottlesDirectory)
        try KelterRemoval.remove(plan.items)
        XCTAssertTrue(fm.fileExists(atPath: paths.bottlesDirectory.appendingPathComponent("A/prefix/drive_c/game.exe").path))
        XCTAssertFalse(fm.fileExists(atPath: paths.runtimesDirectory.path))
    }

    func testNothingInstalledMeansNothingToDelete() {
        let plan = KelterRemoval.plan(paths: paths, library: library, bundleIdentifier: nil, keepBottles: true)
        XCTAssertEqual(plan.items, [])
        XCTAssertNil(plan.keptBottles)
    }

    func testSizeCountsFilesInFolders() throws {
        try makeLibrary()
        XCTAssertGreaterThanOrEqual(KelterRemoval.size(of: paths.bottlesDirectory), 10_000)
        XCTAssertGreaterThan(KelterRemoval.size(of: paths.root), KelterRemoval.size(of: paths.bottlesDirectory))
        XCTAssertEqual(KelterRemoval.size(of: library.appendingPathComponent("missing")), 0)
    }
}
