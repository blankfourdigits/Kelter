import Foundation
import KelterCore

enum ProcessWaiter {
    /// Starts the process and suspends until it has exited.
    static func run(_ process: Process) async throws -> Int32 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                // The process never started, so the handler will not fire.
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Runs a plain helper tool (tar, xattr, softwareupdate …) with its
    /// output going to the log file.
    static func runTool(
        _ executablePath: String,
        _ arguments: [String],
        log: LogFile
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let output = try log.openForAppending()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        log.append("\n$ \(executablePath) \(arguments.joined(separator: " "))\n")
        let status = try await run(process)
        log.append("[beendet mit Status \(status)]\n")
        return status
    }
}
