import Darwin
import Foundation
import XCTest
@testable import KelterWine

final class WineServerStatusTests: XCTestCase {
    func testSocketPathFollowsWinesScheme() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("KelterServer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var info = stat()
        XCTAssertEqual(stat(folder.path, &info), 0)

        let path = try XCTUnwrap(WineServerStatus.socketPath(prefix: folder))
        XCTAssertEqual(
            path,
            "/tmp/.wine-\(getuid())/server-\(String(UInt32(bitPattern: info.st_dev), radix: 16))-\(String(info.st_ino, radix: 16))/socket"
        )
        XCTAssertNil(WineServerStatus.socketPath(prefix: folder.appendingPathComponent("missing")))
    }

    func testOnlyALiveSocketCounts() throws {
        // Short path: Unix socket paths are limited to about 100 bytes.
        let folder = "/tmp/kt-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let path = folder + "/socket"
        XCTAssertFalse(WineServerStatus.isListening(socketPath: path), "no file")

        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertFalse(WineServerStatus.isListening(socketPath: path), "file without a listener")
        XCTAssertEqual(Darwin.listen(server, 1), 0)
        XCTAssertTrue(WineServerStatus.isListening(socketPath: path))
        close(server)
        XCTAssertFalse(WineServerStatus.isListening(socketPath: path), "left behind after a crash")
    }
}
