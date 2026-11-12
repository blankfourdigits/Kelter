import Foundation

/// The one log file everything writes to.
///
/// Wine and its helper processes get this file as stdout and stderr instead of
/// a pipe. Wine leaves background processes (wineserver, services) running
/// after the program you started has quit; with a pipe they would block or
/// die once nobody reads it any more. A file has neither problem, and the UI
/// simply follows it with `LogTailer`.
public final class LogFile: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    /// Creates the file and moves an oversized old log aside.
    public func prepare(maxBytes: UInt64 = 5_000_000) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber,
           size.uint64Value > maxBytes {
            let previous = url.appendingPathExtension("1")
            try? fileManager.removeItem(at: previous)
            try? fileManager.moveItem(at: url, to: previous)
        }
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
    }

    /// Appends text written by Kelter itself.
    public func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        let data = Data(text.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// A handle opened with `O_APPEND`, meant to be handed to a child process
    /// as stdout/stderr. Several processes can append at the same time.
    public func openForAppending() throws -> FileHandle {
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}

/// Reads whatever was appended to a file since the last call.
public final class LogTailer {
    private let url: URL
    private var offset: UInt64 = 0

    public init(url: URL) {
        self.url = url
    }

    /// Ignore everything currently in the file.
    public func skipToEnd() {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        if let end = try? handle.seekToEnd() {
            offset = end
        }
    }

    /// New text since the previous call. If more than `maxBytes` arrived, only
    /// the newest part is returned.
    public func readNew(maxBytes: Int = 256_000) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return "" }
        if end < offset {
            // The file was replaced or truncated: start over.
            offset = 0
        }
        guard end > offset else { return "" }
        var start = offset
        if end - start > UInt64(maxBytes) {
            start = end - UInt64(maxBytes)
        }
        do {
            try handle.seek(toOffset: start)
        } catch {
            return ""
        }
        let data = (try? handle.read(upToCount: Int(end - start))) ?? Data()
        offset = start + UInt64(data.count)
        return String(decoding: data, as: UTF8.self)
    }
}
