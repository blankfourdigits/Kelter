import Foundation
import KelterCore

public enum DownloadError: LocalizedError, Equatable {
    case badStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return loc("Der Download ist fehlgeschlagen (HTTP %@).", "\(code)")
        }
    }
}

/// Downloads one file to disk and reports progress.
public final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: (Double?) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?
    private var lastReportedPercent = -1

    /// - Parameter onProgress: Called with a fraction 0…1, or `nil` if the
    ///   server did not say how big the file is. Not called on the main thread.
    public init(destination: URL, onProgress: @escaping (Double?) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    public func download(from url: URL) async throws {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            if lastReportedPercent != -2 {
                lastReportedPercent = -2
                onProgress(nil)
            }
            return
        }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let percent = Int(fraction * 100)
        // This callback fires thousands of times; only pass on whole percents.
        guard percent != lastReportedPercent else { return }
        lastReportedPercent = percent
        onProgress(fraction)
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temporary file is deleted when this method returns, so it has
        // to be moved right here.
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            failure = DownloadError.badStatus(response.statusCode)
            return
        }
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: location, to: destination)
        } catch {
            failure = error
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let pending = continuation
        continuation = nil
        if let error = error ?? failure {
            pending?.resume(throwing: error)
        } else {
            pending?.resume()
        }
    }
}
