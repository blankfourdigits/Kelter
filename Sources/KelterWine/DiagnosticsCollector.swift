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
        /// Personal details known in advance; they are replaced in every
        /// collected file, together with the patterns `PrivacyRedactor`
        /// knows by itself.
        public var identity: PrivacyRedactor.Identity
        /// Larger files keep their beginning (`headBytes`) and their end, so
        /// both the start-up and the latest events are there.
        public var maxFileBytes: Int
        public var headBytes: Int
        /// Lists the running processes (`ps`); tests pass a fixed text.
        public var processList: @Sendable () throws -> String

        public init(
            logFile: URL,
            runtimeConfig: URL? = nil,
            bottleDirectory: URL? = nil,
            steamDirectory: URL? = nil,
            notes: [String] = [],
            identity: PrivacyRedactor.Identity = PrivacyRedactor.Identity(),
            maxFileBytes: Int = 8_000_000,
            headBytes: Int = 1_000_000,
            processList: @escaping @Sendable () throws -> String = { try DiagnosticsCollector.processList() }
        ) {
            self.logFile = logFile
            self.runtimeConfig = runtimeConfig
            self.bottleDirectory = bottleDirectory
            self.steamDirectory = steamDirectory
            self.notes = notes
            self.identity = identity
            self.maxFileBytes = maxFileBytes
            self.headBytes = headBytes
            self.processList = processList
        }
    }

    public init() {}

    /// One file of the diagnostics folder, still in memory.
    private struct Piece {
        var path: String
        var text: String
        var encoding: String.Encoding
    }

    /// Creates `Kelter-Diagnose-<date>-<time>` inside `parent`, fills it and
    /// returns it. Every file goes through `PrivacyRedactor` first; the
    /// originals stay as they are. A part that cannot be collected is noted
    /// in `fehler.txt` instead of aborting the rest.
    public func collect(_ input: Input, into parent: URL, now: Date = Date()) throws -> URL {
        let fileManager = FileManager.default
        let folder = parent.appendingPathComponent(Self.folderName(for: now), isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        var pieces: [Piece] = []
        var problems: [String] = []
        var shortened: [String] = []
        var skipped: [String] = []
        func attempt(_ label: String, _ work: () throws -> Void) {
            do {
                try work()
            } catch {
                problems.append("\(label): \(error.localizedDescription)")
            }
        }
        func addFile(_ source: URL, as path: String) throws {
            switch try Self.readText(source, maxBytes: input.maxFileBytes, headBytes: input.headBytes) {
            case .text(let text, let encoding, let cut):
                pieces.append(Piece(path: path, text: text, encoding: encoding))
                if cut { shortened.append(path) }
            case .notText:
                skipped.append(path)
            }
        }
        func addText(_ text: String, as path: String) {
            pieces.append(Piece(path: path, text: text, encoding: .utf8))
        }

        attempt("kelter.log") { try addFile(input.logFile, as: "kelter.log") }
        let previousLog = input.logFile.appendingPathExtension("1")
        if fileManager.fileExists(atPath: previousLog.path) {
            attempt("kelter.log.1") { try addFile(previousLog, as: "kelter.log.1") }
        }
        if let runtimeConfig = input.runtimeConfig {
            attempt("runtimes.json") { try addFile(runtimeConfig, as: "runtimes.json") }
        }
        if let bottleDirectory = input.bottleDirectory {
            attempt("bottle.json") {
                try addFile(bottleDirectory.appendingPathComponent("bottle.json"), as: "bottle.json")
            }
        }
        attempt("prozesse.txt") {
            addText(Self.filterProcessList(try input.processList()), as: "prozesse.txt")
        }

        if let steamDirectory = input.steamDirectory {
            // All of Steam's logs: which one helps depends on the fault.
            let logs = steamDirectory.appendingPathComponent("logs", isDirectory: true)
            if fileManager.fileExists(atPath: logs.path) {
                attempt("steam-logs") {
                    for relative in try Self.regularFiles(below: logs, fileManager: fileManager) {
                        attempt("steam-logs/\(relative)") {
                            try addFile(logs.appendingPathComponent(relative), as: "steam-logs/\(relative)")
                        }
                    }
                }
            }
            attempt("spiele.txt") {
                addText(Self.gameListing(steamDirectory: steamDirectory, fileManager: fileManager), as: "spiele.txt")
            }
            attempt("spiel-konsolen") {
                for (source, name) in Self.gameConsoles(steamDirectory: steamDirectory, fileManager: fileManager) {
                    try addFile(source, as: "spiel-konsolen/\(name)")
                }
            }
        }

        attempt("system.txt") {
            var lines = ["Erstellt: \(Self.timestampFormatter.string(from: now))"]
            lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            lines.append(contentsOf: input.notes)
            addText(lines.joined(separator: "\n") + "\n", as: "system.txt")
        }

        // Learn every account first, so its number is replaced in all files.
        let redactor = PrivacyRedactor(identity: input.identity)
        for piece in pieces { redactor.learn(from: piece.text) }
        for piece in pieces {
            attempt(piece.path) {
                let target = folder.appendingPathComponent(piece.path)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let text = redactor.redact(piece.text)
                let data = text.data(using: piece.encoding) ?? Data(text.utf8)
                try data.write(to: target)
            }
        }

        let notice = Self.privacyNotice(
            counts: redactor.counts,
            shortened: shortened,
            skipped: skipped,
            maxFileBytes: input.maxFileBytes
        )
        try? Data(notice.utf8).write(to: folder.appendingPathComponent("datenschutz.txt"))

        if !problems.isEmpty {
            let text = redactor.redact(problems.joined(separator: "\n") + "\n")
            try? Data(text.utf8).write(to: folder.appendingPathComponent("fehler.txt"))
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
    public static func processList() throws -> String {
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
    /// `<game>/<mod>/console.log`. They are collected as
    /// `spiel-konsolen/<game>__<mod>__console.log`.
    static func gameConsoles(steamDirectory: URL, fileManager: FileManager) -> [(URL, String)] {
        let common = steamDirectory.appendingPathComponent("steamapps/common", isDirectory: true)
        guard let games = try? fileManager.contentsOfDirectory(atPath: common.path) else { return [] }
        var result: [(URL, String)] = []
        for game in games.sorted() where !game.hasPrefix(".") {
            let gameFolder = common.appendingPathComponent(game, isDirectory: true)
            var candidates = [gameFolder.appendingPathComponent("console.log")]
            for mod in ((try? fileManager.contentsOfDirectory(atPath: gameFolder.path)) ?? []).sorted() {
                candidates.append(gameFolder.appendingPathComponent(mod).appendingPathComponent("console.log"))
            }
            for console in candidates where fileManager.fileExists(atPath: console.path) {
                let mod = console.deletingLastPathComponent().lastPathComponent
                let name = mod == game ? "\(game)__console.log" : "\(game)__\(mod)__console.log"
                result.append((console, name))
            }
        }
        return result
    }

    /// Paths of all regular files below `directory`, relative to it.
    static func regularFiles(below directory: URL, fileManager: FileManager) throws -> [String] {
        let base = directory.standardizedFileURL.path
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            result.append(String(path.dropFirst(base.count + 1)))
        }
        return result.sorted()
    }

    enum ReadResult: Equatable {
        case text(String, String.Encoding, shortened: Bool)
        case notText
    }

    /// Reads a text file. Files above `maxBytes` keep their first
    /// `headBytes` and their last part, cut at line ends, with a marker line
    /// in between. Files with NUL bytes are not text and are left out,
    /// because they cannot be cleaned.
    static func readText(_ url: URL, maxBytes: Int, headBytes: Int) throws -> ReadResult {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = Int(try handle.seekToEnd())
        try handle.seek(toOffset: 0)

        var data: Data
        var shortened = false
        if size <= maxBytes {
            data = try handle.readToEnd() ?? Data()
        } else {
            let headCount = min(headBytes, maxBytes)
            var head = try handle.read(upToCount: headCount) ?? Data()
            try handle.seek(toOffset: UInt64(size - (maxBytes - headCount)))
            var tail = try handle.readToEnd() ?? Data()
            if let lastNewline = head.lastIndex(of: 0x0A) { head = head[...lastNewline] }
            if let firstNewline = tail.firstIndex(of: 0x0A) { tail = tail[(firstNewline + 1)...] }
            let omitted = size - head.count - tail.count
            let marker = "\n[… Kelter: \(omitted) Bytes in der Mitte ausgelassen / \(omitted) bytes omitted …]\n\n"
            data = Data(head) + Data(marker.utf8) + Data(tail)
            shortened = true
        }
        if data.prefix(65_536).contains(0) { return .notText }
        if let text = String(data: data, encoding: .utf8) {
            return .text(text, .utf8, shortened: shortened)
        }
        // Latin-1 maps every byte, so writing it back keeps the bytes.
        if let text = String(data: data, encoding: .isoLatin1) {
            return .text(text, .isoLatin1, shortened: shortened)
        }
        return .notText
    }

    /// `datenschutz.txt`: what was replaced, and what was not.
    static func privacyNotice(
        counts: [PrivacyRedactor.Category: Int],
        shortened: [String],
        skipped: [String],
        maxFileBytes: Int
    ) -> String {
        var lines: [String] = []
        lines.append("Datenschutz-Hinweis")
        lines.append("===================")
        lines.append("")
        lines.append("Kelter hat beim Sammeln in allen Dateien dieses Ordners nach bekannten")
        lines.append("Mustern für persönliche Angaben gesucht und sie durch Platzhalter wie")
        lines.append("<steamid-1>, <account-1>, <user>, <host> oder <lan-ip-1> ersetzt.")
        lines.append("Die Originaldateien auf diesem Mac sind unverändert.")
        lines.append("")
        lines.append("Gesucht wird nach:")
        lines.append("- SteamIDs und Steam-Kontonummern, Steam-Anmelde- und Anzeigenamen der")
        lines.append("  Konten, die Steam in dieser Bottle kennt")
        lines.append("- dem Mac-Benutzernamen in Dateipfaden, dem vollständigen Namen des")
        lines.append("  Mac-Benutzers und dem Rechnernamen")
        lines.append("- IP-Adressen im eigenen Netz (10.x, 172.16–31.x, 192.168.x, 169.254.x),")
        lines.append("  MAC-Adressen und E-Mail-Adressen")
        lines.append("- Sitzungs- und Token-Kennungen in Steam-Adressen")
        lines.append("")
        lines.append("Ersetzt:")
        let replaced = PrivacyRedactor.Category.allCases.filter { (counts[$0] ?? 0) > 0 }
        if replaced.isEmpty {
            lines.append("- nichts gefunden")
        } else {
            for category in replaced {
                lines.append("- \(category.rawValue): \(counts[category] ?? 0)")
            }
        }
        lines.append("")
        lines.append("Grenzen:")
        lines.append("- Die Suche kennt nur diese Muster. Sie kann Angaben übersehen, zum")
        lines.append("  Beispiel Namen in Ausgaben von Spielen, Chat-Zeilen in Spielkonsolen,")
        lines.append("  Namen von Mitspielern oder Angaben in unbekannter Schreibweise.")
        lines.append("- Namen unter drei Zeichen werden nicht gesucht; der Mac-Benutzername")
        lines.append("  nur in Dateipfaden.")
        lines.append("- Absichtlich nicht ersetzt, weil für die Fehlersuche nötig: installierte")
        lines.append("  Spiele und ihre Dateien, Mac-Modell, Grafikchip, macOS- und")
        lines.append("  Wine-Version, Sprache und Land, Uhrzeiten, öffentliche Adressen von")
        lines.append("  Servern (Steam, Downloads).")
        lines.append("")
        lines.append("Bitte sieh die Dateien durch, bevor du sie weitergibst.")
        lines.append("Kelter verschickt diesen Ordner nicht; er bleibt auf deinem Mac.")
        if !shortened.isEmpty {
            lines.append("")
            lines.append("Gekürzt (größer als \(maxFileBytes / 1_000_000) MB; Anfang und Ende sind da, die Mitte ist markiert):")
            for path in shortened { lines.append("- \(path)") }
        }
        if !skipped.isEmpty {
            lines.append("")
            lines.append("Nicht übernommen, weil keine Textdatei (lässt sich nicht bereinigen):")
            for path in skipped { lines.append("- \(path)") }
        }

        lines.append("")
        lines.append("")
        lines.append("Privacy notice")
        lines.append("==============")
        lines.append("")
        lines.append("While collecting, Kelter searched all files in this folder for known")
        lines.append("patterns of personal details and replaced them with placeholders such")
        lines.append("as <steamid-1>, <account-1>, <user>, <host> or <lan-ip-1>. The original")
        lines.append("files on this Mac are unchanged.")
        lines.append("")
        lines.append("It looks for SteamIDs and account numbers, Steam login and display names")
        lines.append("of the accounts Steam knows in this bottle, the Mac user name in file")
        lines.append("paths, the Mac user's full name, the computer name, addresses in the")
        lines.append("local network, MAC and e-mail addresses, and session or token IDs in")
        lines.append("Steam URLs. The counts are listed above.")
        lines.append("")
        lines.append("It only knows these patterns and can miss details, for example names in")
        lines.append("game output, chat lines in game consoles, other players' names or")
        lines.append("unusual spellings. Names shorter than three characters are not searched;")
        lines.append("the Mac user name only in file paths. Kept on purpose because they are")
        lines.append("needed to find faults: installed games and their files, Mac model, GPU,")
        lines.append("macOS and Wine versions, language and country, times, public server")
        lines.append("addresses.")
        lines.append("")
        lines.append("Please look through the files before you pass them on. Kelter does not")
        lines.append("send this folder anywhere; it stays on your Mac.")
        return lines.joined(separator: "\n") + "\n"
    }
}
