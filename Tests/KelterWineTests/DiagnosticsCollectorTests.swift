import Foundation
import XCTest
import KelterCore
@testable import KelterWine

final class DiagnosticsCollectorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func testFolderNameContainsDateAndTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 21, minute: 45, second: 7))!
        XCTAssertEqual(DiagnosticsCollector.folderName(for: date), "Kelter-Diagnose-20261110-214507")
    }

    func testProcessFilterKeepsHeaderAndWineProcesses() {
        let output = """
          PID ELAPSED COMMAND
            1   10:00 /sbin/launchd
          200   01:00 /Users/x/Library/Application Support/Kelter/Runtimes/wine/11.21/Wine Staging.app/Contents/Resources/wine/bin/wineserver
          201   00:59 C:\\windows\\system32\\services.exe
          202   00:30 C:\\Program Files (x86)\\Steam\\steamapps\\common\\Half-Life 2\\hl2.exe -steam -game hl2
          300   05:00 /Applications/Safari.app/Contents/MacOS/Safari

        """
        let filtered = DiagnosticsCollector.filterProcessList(output)
        let lines = filtered.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].contains("COMMAND"))
        XCTAssertTrue(lines[1].contains("wineserver"))
        XCTAssertTrue(lines[2].contains("services.exe"))
        XCTAssertTrue(lines[3].contains("hl2.exe"))
        XCTAssertFalse(filtered.contains("Safari"))
        XCTAssertFalse(filtered.contains("launchd"))
    }

    func testProcessFilterOnEmptyOutput() {
        XCTAssertEqual(DiagnosticsCollector.filterProcessList(""), "")
    }

    func testProcessListRuns() throws {
        let list = try DiagnosticsCollector.processList()
        XCTAssertTrue(list.contains("PID"))
    }

    func testCollectGathersEverything() throws {
        let log = try write("log line\n", to: "app/Logs/kelter.log")
        _ = try write("old log\n", to: "app/Logs/kelter.log.1")
        let config = try write("{}", to: "app/runtimes.json")
        let bottleJSON = try write("{\"name\":\"Steam\"}", to: "app/Bottles/abc/bottle.json")
        let steam = root.appendingPathComponent("app/Bottles/abc/prefix/drive_c/Steam", isDirectory: true)
        _ = try write("steam console\n", to: "app/Bottles/abc/prefix/drive_c/Steam/logs/console_log.txt")
        _ = try write("exe", to: "app/Bottles/abc/prefix/drive_c/Steam/steamapps/common/Half-Life 2/hl2.exe")
        _ = try write("game console\n", to: "app/Bottles/abc/prefix/drive_c/Steam/steamapps/common/Half-Life 2/hl2/console.log")
        let output = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let input = DiagnosticsCollector.Input(
            logFile: log,
            runtimeConfig: config,
            bottleDirectory: bottleJSON.deletingLastPathComponent(),
            steamDirectory: steam,
            notes: ["Wine: Test 1.0"],
            processList: { "  PID ELAPSED COMMAND\n  200 01:00 wineserver\n" }
        )
        let folder = try DiagnosticsCollector().collect(input, into: output, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(folder.deletingLastPathComponent().path, output.path)
        XCTAssertTrue(folder.lastPathComponent.hasPrefix("Kelter-Diagnose-"))
        XCTAssertEqual(try read(folder.appendingPathComponent("kelter.log")), "log line\n")
        XCTAssertEqual(try read(folder.appendingPathComponent("kelter.log.1")), "old log\n")
        XCTAssertEqual(try read(folder.appendingPathComponent("runtimes.json")), "{}")
        XCTAssertEqual(try read(folder.appendingPathComponent("bottle.json")), "{\"name\":\"Steam\"}")
        XCTAssertEqual(try read(folder.appendingPathComponent("steam-logs/console_log.txt")), "steam console\n")
        XCTAssertEqual(
            try read(folder.appendingPathComponent("spiel-konsolen/Half-Life 2__hl2__console.log")),
            "game console\n"
        )

        let games = try read(folder.appendingPathComponent("spiele.txt"))
        XCTAssertTrue(games.contains("Half-Life 2/"))
        XCTAssertTrue(games.contains("    hl2.exe"))

        let system = try read(folder.appendingPathComponent("system.txt"))
        XCTAssertTrue(system.contains("macOS: "))
        XCTAssertTrue(system.contains("Wine: Test 1.0"))

        XCTAssertTrue(try read(folder.appendingPathComponent("prozesse.txt")).contains("PID"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("fehler.txt").path))
        XCTAssertTrue(try read(folder.appendingPathComponent("datenschutz.txt")).contains("nichts gefunden"))

        // The originals are untouched.
        XCTAssertEqual(try read(log), "log line\n")
    }

    func testCollectNotesWhatIsMissingInsteadOfFailing() throws {
        let missingLog = root.appendingPathComponent("nowhere/kelter.log")
        let input = DiagnosticsCollector.Input(logFile: missingLog, processList: { "  PID COMMAND\n" })

        let folder = try DiagnosticsCollector().collect(input, into: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("kelter.log").path))
        XCTAssertTrue(try read(folder.appendingPathComponent("fehler.txt")).contains("kelter.log"))
        // The parts that do not depend on the log are still there.
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("system.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("prozesse.txt").path))
    }

    func testCollectReplacesPersonalDetailsInEveryFile() throws {
        let log = try write("$ tar -xf /Users/alex/Downloads/wine.tar\n", to: "app/Logs/kelter.log")
        let steam = root.appendingPathComponent("app/Bottles/abc/prefix/drive_c/Steam", isDirectory: true)
        let connection = try write(
            "[Logged On] [U:1:39734314] Logging on, bind 192.168.1.50:27036\n",
            to: "app/Bottles/abc/prefix/drive_c/Steam/logs/connection_log.txt"
        )
        _ = try write(
            "Saving to C:\\users\\alex\\AppData, account 39734314, LOCAL_HOSTNAME=macbook-von-alex\n",
            to: "app/Bottles/abc/prefix/drive_c/Steam/logs/sub/steamsysinfo.txt"
        )
        _ = try write(
            "] status\nname: AlexGamer steamid: [U:1:39734314]\n",
            to: "app/Bottles/abc/prefix/drive_c/Steam/steamapps/common/HL2/hl2/console.log"
        )

        let input = DiagnosticsCollector.Input(
            logFile: log,
            steamDirectory: steam,
            notes: ["Konfiguration: /Users/alex/Documents/Kelter/Resources/runtimes.json"],
            identity: PrivacyRedactor.Identity(userName: "alex", hostNames: ["MacBook von Alex"]),
            processList: { "  PID ELAPSED COMMAND\n  200 01:00 wineserver\n" }
        )
        let folder = try DiagnosticsCollector().collect(input, into: root)

        let collected = try FileManager.default.subpathsOfDirectory(atPath: folder.path)
            .map { folder.appendingPathComponent($0) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .filter { $0.lastPathComponent != "prozesse.txt" && $0.lastPathComponent != "datenschutz.txt" }
        XCTAssertGreaterThanOrEqual(collected.count, 5)
        for file in collected {
            let text = try read(file)
            XCTAssertFalse(text.contains("39734314"), file.lastPathComponent)
            XCTAssertFalse(text.contains("192.168.1.50"), file.lastPathComponent)
            XCTAssertFalse(text.contains("users\\alex"), file.lastPathComponent)
            XCTAssertFalse(text.contains("Users/alex"), file.lastPathComponent)
            XCTAssertFalse(text.contains("macbook-von-alex"), file.lastPathComponent)
        }
        XCTAssertEqual(
            try read(folder.appendingPathComponent("steam-logs/connection_log.txt")),
            "[Logged On] [U:1:<account-1>] Logging on, bind <lan-ip-1>:27036\n"
        )
        // The number seen as [U:1:…] in one file is also replaced bare in another.
        XCTAssertTrue(try read(folder.appendingPathComponent("steam-logs/sub/steamsysinfo.txt")).contains("account <account-1>"))
        let notice = try read(folder.appendingPathComponent("datenschutz.txt"))
        XCTAssertTrue(notice.contains("Steam-Kontonummer: 3"))
        XCTAssertTrue(notice.contains("Bitte sieh die Dateien durch"))
        // The originals are untouched.
        XCTAssertEqual(try read(connection), "[Logged On] [U:1:39734314] Logging on, bind 192.168.1.50:27036\n")
    }

    func testLargeFilesKeepBeginningAndEnd() throws {
        var text = "start line\n"
        for index in 0..<2_000 { text += "middle line \(index)\n" }
        text += "last line\n"
        let url = try write(text, to: "big.txt")

        let result = try DiagnosticsCollector.readText(url, maxBytes: 1_000, headBytes: 300)
        guard case .text(let shortened, _, let cut) = result else { return XCTFail("not text") }
        XCTAssertTrue(cut)
        XCTAssertTrue(shortened.hasPrefix("start line\n"))
        XCTAssertTrue(shortened.hasSuffix("last line\n"))
        XCTAssertTrue(shortened.contains("Bytes in der Mitte ausgelassen"))
        XCTAssertLessThan(shortened.utf8.count, 1_200)
        // Cut at line ends: every line is whole.
        for line in shortened.split(separator: "\n") {
            XCTAssertTrue(line.hasPrefix("start") || line.hasPrefix("middle line ") || line.hasPrefix("last") || line.hasPrefix("[…"))
        }

        guard case .text(let whole, _, let wholeCut) = try DiagnosticsCollector.readText(url, maxBytes: 1_000_000, headBytes: 300)
        else { return XCTFail("not text") }
        XCTAssertFalse(wholeCut)
        XCTAssertEqual(whole, text)
    }

    func testBinaryFilesAreLeftOutAndLatin1IsKept() throws {
        let binary = root.appendingPathComponent("dump.bin")
        try Data([0x4D, 0x44, 0x00, 0x01, 0x02]).write(to: binary)
        XCTAssertEqual(try DiagnosticsCollector.readText(binary, maxBytes: 100, headBytes: 10), .notText)

        let latin = root.appendingPathComponent("latin.txt")
        let bytes = Data([0x47, 0x72, 0xFC, 0xDF, 0x65, 0x0A]) // "Grüße" in Latin-1
        try bytes.write(to: latin)
        guard case .text(let text, let encoding, _) = try DiagnosticsCollector.readText(latin, maxBytes: 100, headBytes: 10)
        else { return XCTFail("not text") }
        XCTAssertEqual(encoding, .isoLatin1)
        XCTAssertEqual(text.data(using: encoding), bytes)
    }
}
