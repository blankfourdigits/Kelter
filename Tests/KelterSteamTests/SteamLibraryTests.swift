import Foundation
import XCTest
@testable import KelterSteam

final class VDFTests: XCTestCase {
    /// Shortened from a real appmanifest of Steam's Windows client.
    static let manifest = """
        "AppState"
        {
        \t"appid"\t\t"2114740"
        \t"Universe"\t\t"1"
        \t"LauncherPath"\t\t"C:\\\\Program Files (x86)\\\\Steam\\\\steam.exe"
        \t"name"\t\t"Blasphemous 2"
        \t"StateFlags"\t\t"4"
        \t"installdir"\t\t"Blasphemous 2"
        \t"LastPlayed"\t\t"1794595364"
        \t"SizeOnDisk"\t\t"4259922825"
        \t"InstalledDepots"
        \t{
        \t\t"2114741"
        \t\t{
        \t\t\t"manifest"\t\t"3607367436135451382"
        \t\t\t"size"\t\t"4231849749"
        \t\t}
        \t}
        \t"UserConfig"
        \t{
        \t\t"language"\t\t"german"
        \t}
        }
        """

    func testParsesNestedObjectsAndEscapes() throws {
        let file = try VDF.parse(Self.manifest)
        let state = try XCTUnwrap(file["AppState"])
        XCTAssertEqual(state["name"]?.string, "Blasphemous 2")
        XCTAssertEqual(state["LauncherPath"]?.string, "C:\\Program Files (x86)\\Steam\\steam.exe")
        XCTAssertEqual(state["InstalledDepots"]?["2114741"]?["size"]?.string, "4231849749")
        XCTAssertEqual(state["UserConfig"]?["language"]?.string, "german")
        XCTAssertEqual(state.entries.first?.key, "appid", "entries keep file order")
    }

    func testKeysIgnoreCaseAndFirstDuplicateWins() throws {
        let file = try VDF.parse(#""Root" { "AppID" "1" "appid" "2" }"#)
        XCTAssertEqual(file["root"]?["appid"]?.string, "1")
        XCTAssertEqual(file["ROOT"]?.entries.count, 2)
    }

    func testSkipsCommentsConditionsAndReadsUnquotedTokens() throws {
        let text = """
            // written by Steam
            "Root"
            {
                "a" "1" [$WIN32]
                b 2
                "c" "line\\nbreak\\t\\"quoted\\""
            }
            """
        let root = try XCTUnwrap(VDF.parse(text)["Root"])
        XCTAssertEqual(root["a"]?.string, "1")
        XCTAssertEqual(root["b"]?.string, "2")
        XCTAssertEqual(root["c"]?.string, "line\nbreak\t\"quoted\"")
    }

    func testBrokenFilesAreErrors() {
        XCTAssertThrowsError(try VDF.parse(#""Root" { "a" "1""#)) { error in
            XCTAssertEqual(error as? VDFError, .unexpectedEnd)
        }
        XCTAssertThrowsError(try VDF.parse("}")) { error in
            XCTAssertEqual(error as? VDFError, .unexpectedToken("}", line: 1))
        }
        XCTAssertThrowsError(try VDF.parse(#""unterminated"#)) { error in
            XCTAssertEqual(error as? VDFError, .unexpectedEnd)
        }
    }

    func testEmptyFileIsAnEmptyObject() throws {
        XCTAssertEqual(try VDF.parse(""), .object([]))
    }
}

final class SteamLibraryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterLibrary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func manifest(id: Int, name: String, dir: String, flags: Int = 4) -> String {
        """
        "AppState"
        {
            "appid"      "\(id)"
            "name"       "\(name)"
            "installdir" "\(dir)"
            "StateFlags" "\(flags)"
            "SizeOnDisk" "1000"
            "LastPlayed" "0"
        }
        """
    }

    /// A bottle with drive C: (Steam) and D: (a second library elsewhere).
    private func makePrefix() throws -> (prefix: URL, steam: URL, external: URL) {
        let fm = FileManager.default
        let prefix = root.appendingPathComponent("prefix", isDirectory: true)
        let steam = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
        let external = root.appendingPathComponent("Volume", isDirectory: true)
        try fm.createDirectory(at: steam, withIntermediateDirectories: true)
        try fm.createDirectory(at: external, withIntermediateDirectories: true)
        let dosdevices = prefix.appendingPathComponent("dosdevices", isDirectory: true)
        try fm.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: dosdevices.appendingPathComponent("c:").path, withDestinationPath: "../drive_c")
        try fm.createSymbolicLink(atPath: dosdevices.appendingPathComponent("d:").path, withDestinationPath: external.path)
        return (prefix, steam, external)
    }

    func testAppFromManifest() throws {
        let library = URL(fileURLWithPath: "/tmp/Steam")
        let app = try XCTUnwrap(SteamLibrary.app(fromManifest: VDF.parse(VDFTests.manifest), library: library))
        XCTAssertEqual(app.appID, 2_114_740)
        XCTAssertEqual(app.name, "Blasphemous 2")
        XCTAssertEqual(app.sizeOnDisk, 4_259_922_825)
        XCTAssertTrue(app.isFullyInstalled)
        XCTAssertEqual(app.lastPlayed, Date(timeIntervalSince1970: 1_794_595_364))
        XCTAssertEqual(app.installURL.path, "/tmp/Steam/steamapps/common/Blasphemous 2")
    }

    func testManifestWithoutNameOrIdIsIgnored() throws {
        let library = URL(fileURLWithPath: "/tmp/Steam")
        XCTAssertNil(SteamLibrary.app(fromManifest: try VDF.parse(#""AppState" { "appid" "1" }"#), library: library))
        XCTAssertNil(SteamLibrary.app(fromManifest: try VDF.parse(#""AppState" { "name" "x" "installdir" "x" }"#),
                                      library: library))
        // Still downloading: listed, but not ready.
        let downloading = try XCTUnwrap(SteamLibrary.app(
            fromManifest: VDF.parse(manifest(id: 5, name: "Neu", dir: "Neu", flags: 1026)), library: library))
        XCTAssertFalse(downloading.isFullyInstalled)
        XCTAssertNil(downloading.lastPlayed, "0 means never played")
    }

    func testLibraryFolderPathsInBothFormats() throws {
        let current = try VDF.parse(#"""
            "libraryfolders"
            {
                "0" { "path" "C:\\Program Files (x86)\\Steam" "apps" { "220" "1" } }
                "1" { "path" "D:\\SteamLibrary" }
            }
            """#)
        XCTAssertEqual(SteamLibrary.libraryFolderPaths(from: current),
                       ["C:\\Program Files (x86)\\Steam", "D:\\SteamLibrary"])
        let old = try VDF.parse(#""LibraryFolders" { "TimeNextStatsReport" "123" "contentstatsid" "4" "1" "E:\\Games" }"#)
        XCTAssertEqual(SteamLibrary.libraryFolderPaths(from: old), ["E:\\Games"])
    }

    func testWindowsPathsThroughDriveLinks() throws {
        let (prefix, steam, external) = try makePrefix()
        XCTAssertEqual(
            SteamLibrary.unixURL(forWindowsPath: "C:\\Program Files (x86)\\Steam", prefix: prefix)?.path,
            steam.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(
            SteamLibrary.unixURL(forWindowsPath: "d:\\SteamLibrary", prefix: prefix)?.path,
            external.resolvingSymlinksInPath().appendingPathComponent("SteamLibrary").path
        )
        XCTAssertNil(SteamLibrary.unixURL(forWindowsPath: "Q:\\Games", prefix: prefix), "unknown drive")
        XCTAssertNil(SteamLibrary.unixURL(forWindowsPath: "\\\\server\\share", prefix: prefix), "no drive letter")
        XCTAssertNil(SteamLibrary.unixURL(forWindowsPath: "C:\\..\\..\\etc", prefix: prefix), "no way out")
    }

    func testScanReadsAllLibrariesOnceAndSortsByName() throws {
        let (prefix, steam, external) = try makePrefix()
        let steamapps = steam.appendingPathComponent("steamapps")
        try write(#"""
            "libraryfolders"
            {
                "0" { "path" "C:\\Program Files (x86)\\Steam" }
                "1" { "path" "D:\\SteamLibrary" }
                "2" { "path" "Q:\\Gone" }
            }
            """#, to: steamapps.appendingPathComponent("libraryfolders.vdf"))
        try write(manifest(id: 420, name: "Half-Life 2: Episode Two", dir: "Half-Life 2"),
                  to: steamapps.appendingPathComponent("appmanifest_420.acf"))
        try write(manifest(id: 220, name: "Half-Life 2", dir: "Half-Life 2"),
                  to: steamapps.appendingPathComponent("appmanifest_220.acf"))
        try write("not a manifest {", to: steamapps.appendingPathComponent("appmanifest_999.acf"))
        try write("ignored", to: steamapps.appendingPathComponent("libraryfolders.acf.bak"))
        let second = external.appendingPathComponent("SteamLibrary/steamapps")
        try write(manifest(id: 1_091_500, name: "Cyberpunk 2077", dir: "Cyberpunk 2077"),
                  to: second.appendingPathComponent("appmanifest_1091500.acf"))
        // The same app in two libraries is listed once (the first one).
        try write(manifest(id: 220, name: "Half-Life 2 (Kopie)", dir: "HL2"),
                  to: second.appendingPathComponent("appmanifest_220.acf"))

        let apps = SteamLibrary.scan(steamDirectory: steam, prefix: prefix)

        XCTAssertEqual(apps.map(\.name), ["Cyberpunk 2077", "Half-Life 2", "Half-Life 2: Episode Two"])
        XCTAssertEqual(apps[0].library.resolvingSymlinksInPath().path,
                       external.appendingPathComponent("SteamLibrary").resolvingSymlinksInPath().path)
        XCTAssertEqual(apps[1].installDirectory, "Half-Life 2")
    }

    func testScanWithoutSteamFindsNothing() throws {
        let (prefix, steam, _) = try makePrefix()
        XCTAssertEqual(SteamLibrary.scan(steamDirectory: steam, prefix: prefix), [])
    }
}
