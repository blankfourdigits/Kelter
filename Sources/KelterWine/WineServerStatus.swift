import Darwin
import Foundation

/// Tells whether Wine is running in a prefix, without starting anything:
/// every running prefix has a wineserver listening on a socket whose path
/// Wine derives from the prefix folder's device and inode numbers
/// (`/tmp/.wine-<uid>/server-<dev>-<ino>/socket`, see Wine's
/// dlls/ntdll/unix/server.c).
public enum WineServerStatus {
    /// Where the wineserver of `prefix` listens, or `nil` if the folder
    /// does not exist.
    public static func socketPath(prefix: URL, baseDirectory: String? = nil) -> String? {
        var info = stat()
        guard stat(prefix.path, &info) == 0 else { return nil }
        let base = baseDirectory ?? "/tmp/.wine-\(getuid())"
        let device = String(UInt64(UInt32(bitPattern: info.st_dev)), radix: 16)
        let inode = String(UInt64(info.st_ino), radix: 16)
        return "\(base)/server-\(device)-\(inode)/socket"
    }

    /// Whether something accepts connections on the Unix socket. A socket
    /// file left behind by a crashed wineserver does not count.
    public static func isListening(socketPath path: String) -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxLength else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, length) }
        }
        return result == 0
    }

    /// Whether any Wine program (Steam, a game, an installer) is running in
    /// the prefix.
    public static func isRunning(prefix: URL) -> Bool {
        guard let path = socketPath(prefix: prefix) else { return false }
        return isListening(socketPath: path)
    }
}
