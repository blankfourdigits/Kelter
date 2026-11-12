import Foundation
import XCTest
@testable import KelterCore

final class BottleStoreTests: XCTestCase {
    private var directory: URL!
    private var store: BottleStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = BottleStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testEmptyStoreListsNothing() throws {
        XCTAssertEqual(try store.list(), [])
    }

    func testMissingDirectoryListsNothing() throws {
        let missing = BottleStore(directory: directory.appendingPathComponent("does-not-exist"))
        XCTAssertEqual(try missing.list(), [])
    }

    func testCreateWritesMetadataAndPrefix() throws {
        let bottle = try store.create(name: "Steam")

        XCTAssertEqual(bottle.name, "Steam")
        XCTAssertEqual(bottle.settings, BottleSettings())
        XCTAssertEqual(bottle.settings.windowsVersion, .win10)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.prefixURL(for: bottle.id).path,
            isDirectory: &isDirectory
        ))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.directory(for: bottle.id).appendingPathComponent("bottle.json").path
        ))
    }

    func testCreatedBottleSurvivesReload() throws {
        var settings = BottleSettings()
        settings.windowsVersion = .win11
        settings.metalHUD = true
        settings.environment = ["FOO": "bar"]
        settings.dllOverrides = ["d3d11": "n,b"]
        let created = try store.create(name: "Spiele", settings: settings)

        let reloaded = try BottleStore(directory: directory).list()
        XCTAssertEqual(reloaded, [created])
    }

    func testNameIsTrimmed() throws {
        let bottle = try store.create(name: "  Steam \n")
        XCTAssertEqual(bottle.name, "Steam")
    }

    func testEmptyNameIsRejected() {
        XCTAssertThrowsError(try store.create(name: "   ")) { error in
            XCTAssertEqual(error as? BottleStoreError, .emptyName)
        }
        XCTAssertEqual(try store.list(), [])
    }

    func testDuplicateNameIsRejectedIgnoringCase() throws {
        try store.create(name: "Steam")
        XCTAssertThrowsError(try store.create(name: "steam")) { error in
            XCTAssertEqual(error as? BottleStoreError, .duplicateName("steam"))
        }
        XCTAssertEqual(try store.list().count, 1)
    }

    func testRename() throws {
        let bottle = try store.create(name: "Alt")
        let renamed = try store.rename(bottle.id, to: "Neu")

        XCTAssertEqual(renamed.id, bottle.id)
        XCTAssertEqual(renamed.name, "Neu")
        XCTAssertEqual(try store.list().map(\.name), ["Neu"])
        // Renaming must not move the prefix.
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.prefixURL(for: bottle.id).path))
    }

    func testRenameToOwnNameWithDifferentCaseIsAllowed() throws {
        let bottle = try store.create(name: "steam")
        let renamed = try store.rename(bottle.id, to: "Steam")
        XCTAssertEqual(renamed.name, "Steam")
    }

    func testRenameToExistingNameIsRejected() throws {
        try store.create(name: "Eins")
        let second = try store.create(name: "Zwei")
        XCTAssertThrowsError(try store.rename(second.id, to: "Eins")) { error in
            XCTAssertEqual(error as? BottleStoreError, .duplicateName("Eins"))
        }
        XCTAssertEqual(try store.bottle(id: second.id).name, "Zwei")
    }

    func testRenameUnknownBottleFails() {
        let id = UUID()
        XCTAssertThrowsError(try store.rename(id, to: "Egal")) { error in
            XCTAssertEqual(error as? BottleStoreError, .notFound(id))
        }
    }

    func testUpdateSavesSettings() throws {
        var bottle = try store.create(name: "Steam")
        bottle.settings.retinaMode = true
        bottle.settings.graphicsBackend = .wined3d
        try store.update(bottle)

        let reloaded = try store.bottle(id: bottle.id)
        XCTAssertTrue(reloaded.settings.retinaMode)
        XCTAssertEqual(reloaded.settings.graphicsBackend, .wined3d)
    }

    func testUpdateUnknownBottleFails() {
        let ghost = Bottle(name: "Geist", createdAt: Date())
        XCTAssertThrowsError(try store.update(ghost)) { error in
            XCTAssertEqual(error as? BottleStoreError, .notFound(ghost.id))
        }
        XCTAssertEqual(try store.list(), [])
    }

    func testDeleteRemovesEverything() throws {
        let keep = try store.create(name: "Bleibt")
        let remove = try store.create(name: "Weg")
        let marker = store.prefixURL(for: remove.id).appendingPathComponent("drive_c.txt")
        try Data("x".utf8).write(to: marker)

        try store.delete(remove.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(for: remove.id).path))
        XCTAssertEqual(try store.list(), [keep])
    }

    func testDeleteUnknownBottleFails() {
        let id = UUID()
        XCTAssertThrowsError(try store.delete(id)) { error in
            XCTAssertEqual(error as? BottleStoreError, .notFound(id))
        }
    }

    func testListIgnoresForeignAndBrokenFolders() throws {
        let bottle = try store.create(name: "Echt")

        // Not a UUID.
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Notizen"),
            withIntermediateDirectories: true
        )
        // A UUID folder without metadata.
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(UUID().uuidString),
            withIntermediateDirectories: true
        )
        // A UUID folder with unreadable metadata.
        let broken = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("kein json".utf8).write(to: broken.appendingPathComponent("bottle.json"))

        XCTAssertEqual(try store.list(), [bottle])
    }

    func testListIsSortedByCreationDate() throws {
        let older = Bottle(name: "Zuerst", createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = Bottle(name: "Danach", createdAt: Date(timeIntervalSince1970: 2_000))
        for bottle in [newer, older] {
            let folder = store.directory(for: bottle.id)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(bottle).write(to: folder.appendingPathComponent("bottle.json"))
        }
        XCTAssertEqual(try store.list().map(\.name), ["Zuerst", "Danach"])
    }

    func testSettingsWithMissingKeysUseDefaults() throws {
        // A bottle.json written before newer settings existed.
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "Alt",
          "createdAt": "2026-01-02T03:04:05Z",
          "settings": { "windowsVersion": "win7" }
        }
        """
        let folder = store.directory(for: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: folder.appendingPathComponent("bottle.json"))

        let bottle = try store.bottle(id: id)
        XCTAssertEqual(bottle.name, "Alt")
        XCTAssertEqual(bottle.settings.windowsVersion, .win7)
        XCTAssertEqual(bottle.settings.graphicsBackend, .dxmt)
        XCTAssertFalse(bottle.settings.retinaMode)
        XCTAssertEqual(bottle.settings.environment, [:])
        XCTAssertNil(bottle.settings.steamArguments)
        XCTAssertNil(bottle.settings.steamBrowserArguments)
        XCTAssertFalse(bottle.settings.verboseLogging)
    }

    func testSteamArgumentsSurviveReload() throws {
        var bottle = try store.create(name: "Steam")
        XCTAssertNil(try store.bottle(id: bottle.id).settings.steamArguments)

        bottle.settings.steamArguments = ["-cef-disable-gpu", "-silent"]
        try store.update(bottle)
        XCTAssertEqual(try store.bottle(id: bottle.id).settings.steamArguments, ["-cef-disable-gpu", "-silent"])

        // Empty is a value of its own and must not turn back into nil.
        bottle.settings.steamArguments = []
        try store.update(bottle)
        XCTAssertEqual(try store.bottle(id: bottle.id).settings.steamArguments, [])
    }

    func testRendererIDsPerGraphicsBackend() {
        XCTAssertEqual(GraphicsBackendKind.wined3d.rendererIDs, [])
        XCTAssertEqual(GraphicsBackendKind.dxmt.rendererIDs, ["d9vk", "dxmt"])
        XCTAssertEqual(GraphicsBackendKind.dxvk.rendererIDs, ["d9vk", "dxvk"])
        XCTAssertEqual(GraphicsBackendKind.d3dmetal.rendererIDs, ["d9vk", "dxmt", "d3dmetal"])
    }

    func testNewBottlesUseDXMT() throws {
        XCTAssertEqual(try store.create(name: "Neu").settings.graphicsBackend, .dxmt)
    }
}
