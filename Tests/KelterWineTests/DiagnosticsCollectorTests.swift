import Foundation
import XCTest
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
            notes: ["Wine: Test 1.0"]
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

        // The originals are untouched.
        XCTAssertEqual(try read(log), "log line\n")
    }

    func testCollectNotesWhatIsMissingInsteadOfFailing() throws {
        let missingLog = root.appendingPathComponent("nowhere/kelter.log")
        let input = DiagnosticsCollector.Input(logFile: missingLog)

        let folder = try DiagnosticsCollector().collect(input, into: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("kelter.log").path))
        XCTAssertTrue(try read(folder.appendingPathComponent("fehler.txt")).contains("kelter.log"))
        // The parts that do not depend on the log are still there.
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("system.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("prozesse.txt").path))
    }
}
