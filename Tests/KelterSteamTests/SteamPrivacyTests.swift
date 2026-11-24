import Foundation
import XCTest
import KelterCore
@testable import KelterSteam

final class SteamPrivacyTests: XCTestCase {
    func testReadsAccountsFromLoginUsersAndUserdata() throws {
        let steam = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterSteamPrivacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: steam) }
        try FileManager.default.createDirectory(at: steam.appendingPathComponent("config"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: steam.appendingPathComponent("userdata/42"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: steam.appendingPathComponent("userdata/anonymous"), withIntermediateDirectories: true)
        try Data("""
        "users"
        {
            "76561198000000042"
            {
                "AccountName"   "alexgamer77"
                "PersonaName"   "Der Alex"
                "RememberPassword"  "1"
            }
        }
        """.utf8).write(to: steam.appendingPathComponent("config/loginusers.vdf"))

        let identity = SteamPrivacy.identity(adding: steam, to: PrivacyRedactor.Identity(userName: "alex"))

        XCTAssertEqual(identity.userName, "alex")
        XCTAssertEqual(identity.steamAccountNames, ["alexgamer77"])
        XCTAssertEqual(identity.steamPersonaNames, ["Der Alex"])
        XCTAssertEqual(identity.steamAccountIDs, [42, 39_734_314])
    }

    func testWithoutSteamFilesNothingIsAdded() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let base = PrivacyRedactor.Identity(userName: "alex")
        XCTAssertEqual(SteamPrivacy.identity(adding: missing, to: base), base)
    }
}
