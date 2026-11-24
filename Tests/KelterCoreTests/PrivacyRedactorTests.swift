import Foundation
import XCTest
@testable import KelterCore

final class PrivacyRedactorTests: XCTestCase {
    private let identity = PrivacyRedactor.Identity(
        userName: "alex",
        fullName: "Alex Beispiel",
        hostNames: ["MacBook Pro von Alex", "MacBook-Pro-von-Alex"],
        steamAccountNames: ["alexgamer77"],
        steamPersonaNames: ["Der Alex"],
        steamAccountIDs: [39_734_314]
    )

    func testSteamIDsAreReplacedConsistently() {
        let redactor = PrivacyRedactor(identity: identity)
        let text = """
        [Logged On] [U:1:39734314] Logging on [U:1:39734314]
        -steamid=76561198000000042 cloud for account 39734314
        anonymous [U:1:0]
        """
        let result = redactor.redact(text)
        XCTAssertFalse(result.contains("39734314"))
        XCTAssertFalse(result.contains("76561198000000042"))
        XCTAssertTrue(result.contains("[U:1:<account-1>] Logging on [U:1:<account-1>]"))
        XCTAssertTrue(result.contains("-steamid=<steamid-1>"))
        XCTAssertTrue(result.contains("account <account-1>"))
        // Anonymous logon stays readable.
        XCTAssertTrue(result.contains("[U:1:0]"))
    }

    func testOtherAccountsGetOwnNumbersAndAreLearned() {
        let redactor = PrivacyRedactor(identity: identity)
        let other = "user [U:1:12345678] joined"
        redactor.learn(from: other)
        let result = redactor.redact("friend 12345678 and [U:1:39734314]")
        XCTAssertEqual(result, "friend <account-2> and [U:1:<account-1>]")
        XCTAssertEqual(redactor.redact(other), "user [U:1:<account-2>] joined")
    }

    func testUserNameOnlyInPaths() {
        let redactor = PrivacyRedactor(identity: identity)
        let text = """
        /Users/alex/Library/Application Support/Kelter
        C:\\users\\alex\\AppData\\Local\\Temp\\D966.tmp
        {"path":"C:\\\\users\\\\alex\\\\Documents"}
        drive_c/users/alex/AppData
        alex fps 60, alexander 120, /Users/alexa/x
        """
        let result = redactor.redact(text)
        XCTAssertTrue(result.contains("/Users/<user>/Library"))
        XCTAssertTrue(result.contains("C:\\users\\<user>\\AppData"))
        XCTAssertTrue(result.contains("C:\\\\users\\\\<user>\\\\Documents"))
        XCTAssertTrue(result.contains("drive_c/users/<user>/AppData"))
        // Ordinary words and other users are kept.
        XCTAssertTrue(result.contains("alex fps 60, alexander 120, /Users/alexa/x"))
    }

    func testHostAndNames() {
        let redactor = PrivacyRedactor(identity: identity)
        let text = """
        ?LOCAL_HOSTNAME=macbook-pro-von-alex&LANGUAGE=german
        MacBook-Pro-von-Alex.local
        Login: OnLoginStateChange alexgamer77 3 1 0 0
        persona Der Alex online; owner Alex Beispiel
        """
        let result = redactor.redact(text)
        XCTAssertTrue(result.contains("LOCAL_HOSTNAME=<host>&LANGUAGE=german"))
        XCTAssertTrue(result.contains("<host>.local"))
        XCTAssertTrue(result.contains("OnLoginStateChange <steam-login-1> 3 1 0 0"))
        XCTAssertTrue(result.contains("persona <steam-name-1> online"))
        XCTAssertTrue(result.contains("owner <full-name>"))
        XCTAssertFalse(result.lowercased().contains("alex"))
    }

    func testShortNamesAreNotSearched() {
        let redactor = PrivacyRedactor(identity: PrivacyRedactor.Identity(steamPersonaNames: ["Al"]))
        XCTAssertEqual(redactor.redact("Al loaded all dlls"), "Al loaded all dlls")
    }

    func testNetworkAddresses() {
        let redactor = PrivacyRedactor(identity: identity)
        let text = """
        Could not bind socket to 192.168.1.50:27036
        bind 192.168.1.50 again, router 192.168.1.1, vpn 10.8.0.2, docker 172.20.110.115
        server 203.0.113.7:27017 local 127.0.0.1 any 0.0.0.0 public 172.32.1.1
        version 1.2.3.4.5 file 10.0.19041.1
        mac 02:00:00:12:34:56 mail alex@example.org
        """
        let result = redactor.redact(text)
        XCTAssertTrue(result.contains("socket to <lan-ip-1>:27036"))
        XCTAssertTrue(result.contains("bind <lan-ip-1> again, router <lan-ip-2>, vpn <lan-ip-3>, docker <lan-ip-4>"))
        XCTAssertTrue(result.contains("server 203.0.113.7:27017 local 127.0.0.1 any 0.0.0.0 public 172.32.1.1"))
        XCTAssertTrue(result.contains("version 1.2.3.4.5 file 10.0.19041.1"))
        XCTAssertTrue(result.contains("mac <mac-address> mail <email>"))
        XCTAssertEqual(redactor.counts[.lanAddress], 5)
    }

    func testSecrets() {
        let redactor = PrivacyRedactor(identity: identity)
        let text = """
        https://steamcommunity.com/textfilter/ajaxgetcommunitypreferences?sessionid=abcd1234&l=german
        Using JWT 11111111111111111, persistence: 1
        access_token=eyJhbGci.xyz refresh_token=abc; steamLoginSecure=7656%7C%7Cabc
        (More info: https://goo.gl/AbCdEf) password field
        """
        let result = redactor.redact(text)
        XCTAssertTrue(result.contains("?sessionid=<redacted>&l=german"))
        XCTAssertTrue(result.contains("Using JWT <redacted>, persistence: 1"))
        XCTAssertTrue(result.contains("access_token=<redacted> refresh_token=<redacted>; steamLoginSecure=<redacted>"))
        XCTAssertTrue(result.contains("(More info: https://goo.gl/AbCdEf) password field"))
    }

    func testTextWithoutPersonalDetailsIsUnchanged() {
        let redactor = PrivacyRedactor(identity: identity)
        let text = "0024:fixme:d3d:wined3d_check_device_format Unhandled format.\n[2026-11-20 19:50:26] AppID 1687950 adding PID 1234\n"
        XCTAssertEqual(redactor.redact(text), text)
        XCTAssertTrue(redactor.counts.isEmpty)
    }

    func testHomeIsAbbreviated() {
        XCTAssertEqual(
            PrivacyRedactor.abbreviatingHome(
                "$ /usr/bin/tar -xf /Users/alex/Library/x.tar -C /Users/alex\n/Users/alexa/y",
                home: "/Users/alex"
            ),
            "$ /usr/bin/tar -xf ~/Library/x.tar -C ~\n/Users/alexa/y"
        )
    }

    func testLogFileWritesHomeAsTilde() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KelterLog-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = LogFile(url: url, homeDirectory: "/Users/alex")
        try log.prepare()
        log.append("Wine ist installiert: /Users/alex/Library/Application Support/Kelter\n")
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8),
            "Wine ist installiert: ~/Library/Application Support/Kelter\n"
        )
    }
}
