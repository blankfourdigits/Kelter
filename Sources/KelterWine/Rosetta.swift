import Foundation
import KelterCore

/// Wine for macOS is an Intel (x86_64) program, so Apple Silicon Macs need
/// Rosetta 2 to run it.
public enum Rosetta {
    /// True if Intel programs can run. Tested by actually running one, which
    /// is more reliable than looking for Rosetta's files.
    public static func isInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// The command a user can run by hand if the automatic install fails.
    public static let manualCommand = "softwareupdate --install-rosetta --agree-to-license"

    /// Installs Rosetta 2 through Apple's software update tool. Returns true
    /// if Intel programs run afterwards.
    public static func install(log: LogFile) async throws -> Bool {
        _ = try await ProcessWaiter.runTool(
            "/usr/sbin/softwareupdate",
            ["--install-rosetta", "--agree-to-license"],
            log: log
        )
        return isInstalled()
    }
}
