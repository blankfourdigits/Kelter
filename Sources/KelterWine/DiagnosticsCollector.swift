import Foundation
import KelterCore

/// Gathers everything needed to find out why a program does not start into
/// one folder: Kelter's log, the bottle's settings, Steam's own logs, the
/// running Wine processes and the consoles of Source engine games.
///
/// Nothing leaves the Mac; the folder is for the user to look at or pass on.
public struct DiagnosticsCollector: Sendable {
    public struct Input: Sendable {
        /// Kelter's log file.
        public var logFile: URL
        /// The `runtimes.json` in use, if known.
        public var runtimeConfig: URL?
        /// The selected bottle's folder (contains `bottle.json`), if any.
        public var bottleDirectory: URL?
        /// The Steam folder inside that bottle, if Steam is installed.
        public var steamDirectory: URL?
        /// Free-form lines for `system.txt` (versions, settings).
        public var notes: [String]

        public init(
            logFile: URL,
            runtimeConfig: URL? = nil,
            bottleDirectory: URL? = nil,
            steamDirectory: URL? = nil,
            notes: [String] = []
        ) {
            self.logFile = logFile
            self.runtimeConfig = runtimeConfig
            self.bottleDirectory = bottleDirectory
            self.steamDirectory = steamDirectory
            self.notes = notes
        }
    }

    public init() {}

    /// Creates `Kelter-Diagnose-<date>-<time>` inside `parent`, fills it and
    /// returns it. A part that cannot be collected is noted in `fehler.txt`
    /// instead of aborting the rest.
    public func collect(_ input: Input, into parent: URL, now: Date = Date()) throws -> URL {
        let fileManager = FileManager.default
        let folder = parent.appendingPathComponent(Self.folderName(for: now), isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        var problems: [String] = []
        func attempt(_ label: String, _ work: () throws -> Void) {
            do {
                try work()
            } catch {
                problems.append("\(label): \(error.localizedDescription)")
            }
        }

        attempt("kelter.log") {
            try fileManager.copyItem(at: input.logFile, to: folder.appendingPathComponent("kelter.log"))
        }
        let previousLog = input.logFile.appendingPathExtension("1")
        if fileManager.fileExists(atPath: previousLog.path) {
            attempt("kelter.log.1") {
                try fileManager.copyItem(at: previousLog, to: folder.appendingPathComponent("kelter.log.1"))
            }
        }

        if let runtimeConfig = input.runtimeConfig {
            attempt("runtimes.json") {
                try fileManager.copyItem(at: runtimeConfig, to: folder.appendingPathComponent("runtimes.json"))
            }
        }

        if let bottleDirectory = input.bottleDirectory {
            attempt("bottle.json") {
                try fileManager.copyItem(
                    at: bottleDirectory.appendingPathComponent("bottle.json"),
                    to: folder.appendingPathComponent("bottle.json")
                )
            }
        }

        attempt("prozesse.txt") {
            let list = Self.filterProcessList(try Self.processList())
            try Data(list.utf8).write(to: folder.appendingPathComponent("prozesse.txt"))
        }

        if let steamDirectory = input.steamDirectory {
            let logs = steamDirectory.appendingPathComponent("logs", isDirectory: true)
            if fileManager.fileExists(atPath: logs.path) {
                attempt("steam-logs") {
                    try fileManager.copyItem(at: logs, to: folder.appendingPathComponent("steam-logs"))
                }
            }
            attempt("spiele.txt") {
                let listing = Self.gameListing(steamDirectory: steamDirectory, fileManager: fileManager)
                try Data(listing.utf8).write(to: folder.appendingPathComponent("spiele.txt"))
            }
            attempt("spiel-konsolen") {
                try Self.copyGameConsoles(steamDirectory: steamDirectory, into: folder, fileManager: fileManager)
            }
        }

        attempt("system.txt") {
            var lines = ["Erstellt: \(Self.timestampFormatter.string(from: now))"]
            lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            lines.append(contentsOf: input.notes)
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: folder.appendingPathComponent("system.txt"))
        }

        if !problems.isEmpty {
            try? Data((problems.joined(separator: "\n") + "\n").utf8)
                .write(to: folder.appendingPathComponent("fehler.txt"))
        }
        return folder
    }

    // MARK: Pieces

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    static func folderName(for date: Date) -> String {
        "Kelter-Diagnose-" + timestampFormatter.string(from: date)
    }

    /// All processes of this user, with how long they have been running.
    static func processList() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["axww", "-o", "pid,etime,command"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // ps ends on its own and starts no children, so reading to the end
        // cannot hang.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Keeps the header and the lines that belong to Wine: Wine's own
    /// programs, and Windows programs (their command starts with `C:\`).
    static func filterProcessList(_ output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let header = lines.first else { return "" }
        let kept = lines.dropFirst().filter { line in
            let lowered = line.lowercased()
            return lowered.contains("wine") || lowered.contains(":\\")
        }
        return ([header] + kept).joined(separator: "\n") + "\n"
    }

    /// The installed games (folders below `steamapps/common`) and the files
    /// at the top of each.
    static func gameListing(steamDirectory: URL, fileManager: FileManager) -> String {
        let common = steamDirectory.appendingPathComponent("steamapps/common", isDirectory: true)
        guard let games = try? fileManager.contentsOfDirectory(atPath: common.path) else {
            return "Kein Ordner steamapps/common.\n"
        }
        var lines: [String] = []
        for game in games.sorted() where !game.hasPrefix(".") {
            lines.append(game + "/")
            let entries = (try? fileManager.contentsOfDirectory(atPath: common.appendingPathComponent(game).path)) ?? []
            for entry in entries.sorted() where !entry.hasPrefix(".") {
                lines.append("    " + entry)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Source engine games started with `-condebug` write
    /// `<game>/<mod>/console.log`. Those are copied as
    /// `spiel-konsolen/<game>__<mod>__console.log`.
    static func copyGameConsoles(steamDirectory: URL, into folder: URL, fileManager: FileManager) throws {
        let common = steamDirectory.appendingPathComponent("steamapps/common", isDirectory: true)
        guard let games = try? fileManager.contentsOfDirectory(atPath: common.path) else { return }
        let target = folder.appendingPathComponent("spiel-konsolen", isDirectory: true)
        var created = false
        for game in games where !game.hasPrefix(".") {
            let gameFolder = common.appendingPathComponent(game, isDirectory: true)
            var candidates = [gameFolder.appendingPathComponent("console.log")]
            for mod in (try? fileManager.contentsOfDirectory(atPath: gameFolder.path)) ?? [] {
                candidates.append(gameFolder.appendingPathComponent(mod).appendingPathComponent("console.log"))
            }
            for console in candidates where fileManager.fileExists(atPath: console.path) {
                if !created {
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                    created = true
                }
                let mod = console.deletingLastPathComponent().lastPathComponent
                let name = mod == game ? "\(game)__console.log" : "\(game)__\(mod)__console.log"
                try fileManager.copyItem(at: console, to: target.appendingPathComponent(name))
            }
        }
    }
}
