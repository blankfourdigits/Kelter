import Foundation

/// Follows Steam's log of the game processes it tracks
/// (`logs/gameprocess_log.txt`), which tells when a started game is
/// actually running and when it has ended:
///
///     AppID 1687950 adding PID 1960 as a tracked process "…\P5R.exe"
///     AppID 1687950 no longer tracking PID 1960, exit code 0
public struct SteamGameProcessLog: Sendable {
    public enum Event: Equatable, Sendable {
        case started(appID: Int)
        case ended(appID: Int)
    }

    public let file: URL
    /// Bytes already read; only lines written later count.
    private(set) var offset: UInt64
    /// Processes Steam tracks per app (a launcher and the game may both be).
    private(set) var tracked: [Int: Int] = [:]

    /// Starts at the current end of the file, so earlier sessions don't count.
    public init(file: URL, fileManager: FileManager = .default) {
        self.file = file
        let size = (try? fileManager.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.uint64Value
        self.offset = size ?? 0
    }

    /// Whether Steam currently tracks a process of the app.
    public func isRunning(appID: Int) -> Bool {
        (tracked[appID] ?? 0) > 0
    }

    /// Reads what Steam has written since the last call and returns it as
    /// events. A file that got shorter (Steam starts a new one) is read
    /// from the beginning.
    public mutating func poll(fileManager: FileManager = .default) -> [Event] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0 }
        guard size > offset else { return [] }
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        // Keep an unfinished last line for the next call.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
        let complete = data[data.startIndex...lastNewline]
        offset += UInt64(complete.count)
        let events = Self.events(in: String(decoding: complete, as: UTF8.self))
        for event in events {
            switch event {
            case .started(let appID):
                tracked[appID, default: 0] += 1
            case .ended(let appID):
                tracked[appID] = max(0, (tracked[appID] ?? 0) - 1)
            }
        }
        return events
    }

    /// The events in a piece of the log, in order.
    static func events(in text: String) -> [Event] {
        var events: [Event] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: "AppID ") else { continue }
            let rest = line[range.upperBound...]
            let digits = rest.prefix(while: \.isNumber)
            guard let appID = Int(digits) else { continue }
            let after = rest.dropFirst(digits.count)
            if after.hasPrefix(" adding PID ") {
                events.append(.started(appID: appID))
            } else if after.hasPrefix(" no longer tracking PID ") {
                events.append(.ended(appID: appID))
            }
        }
        return events
    }
}
