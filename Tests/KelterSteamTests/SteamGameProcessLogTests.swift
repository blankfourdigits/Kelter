import Foundation
import XCTest
@testable import KelterSteam

final class SteamGameProcessLogTests: XCTestCase {
    private var file: URL!

    override func setUpWithError() throws {
        file = FileManager.default.temporaryDirectory
            .appendingPathComponent("kelter-gameprocess-\(UUID().uuidString).txt")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file)
    }

    private func append(_ text: String) throws {
        if let handle = try? FileHandle(forWritingTo: file) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: file)
        }
    }

    func testReadsStartAndEndLines() {
        let text = """
            [2026-11-24 10:11:55] AppID 1687950 adding PID 1960 as a tracked process ""C:\\Steam\\P5R.exe""
            [2026-11-24 10:11:55] SSGL: InternalUpdateClientGame indicates change to games list
            [2026-11-24 10:13:08] AppID 1687950 no longer tracking PID 1960, exit code 1
            [2026-11-24 10:13:08] Remove 1687950 from running list
            """
        XCTAssertEqual(SteamGameProcessLog.events(in: text), [.started(appID: 1687950), .ended(appID: 1687950)])
    }

    func testIgnoresWhatWasThereBefore() throws {
        try append("[x] AppID 220 adding PID 1 as a tracked process \"a\"\n")
        var log = SteamGameProcessLog(file: file)
        XCTAssertEqual(log.poll(), [])
        XCTAssertFalse(log.isRunning(appID: 220))
        try append("[x] AppID 220 adding PID 2 as a tracked process \"a\"\n")
        XCTAssertEqual(log.poll(), [.started(appID: 220)])
        XCTAssertTrue(log.isRunning(appID: 220))
    }

    func testCountsSeveralProcessesOfOneGame() throws {
        try append("")
        var log = SteamGameProcessLog(file: file)
        try append("""
            [x] AppID 5 adding PID 1 as a tracked process "launcher.exe"
            [x] AppID 5 adding PID 2 as a tracked process "game.exe"
            [x] AppID 5 no longer tracking PID 1, exit code 0

            """)
        _ = log.poll()
        XCTAssertTrue(log.isRunning(appID: 5), "the game itself still runs")
        try append("[x] AppID 5 no longer tracking PID 2, exit code 0\n")
        _ = log.poll()
        XCTAssertFalse(log.isRunning(appID: 5))
    }

    func testWaitsForCompleteLines() throws {
        try append("")
        var log = SteamGameProcessLog(file: file)
        try append("[x] AppID 7 adding PID 1 as a tracked")
        XCTAssertEqual(log.poll(), [])
        try append(" process \"g.exe\"\n")
        XCTAssertEqual(log.poll(), [.started(appID: 7)])
    }

    func testStartsOverWhenSteamBeginsANewFile() throws {
        try append(String(repeating: "old line\n", count: 50))
        var log = SteamGameProcessLog(file: file)
        try Data("[x] AppID 9 adding PID 1 as a tracked process \"g\"\n".utf8).write(to: file)
        XCTAssertEqual(log.poll(), [.started(appID: 9)])
    }

    func testMissingFileIsQuiet() {
        var log = SteamGameProcessLog(file: file)
        XCTAssertEqual(log.poll(), [])
    }
}
