import Foundation

/// What removing Kelter from the Mac deletes, besides the app itself.
public struct KelterRemovalPlan: Equatable, Sendable {
    /// Folders and files to delete, existing ones only.
    public var items: [URL]
    /// The bottles folder, if it is kept.
    public var keptBottles: URL?

    public init(items: [URL], keptBottles: URL?) {
        self.items = items
        self.keptBottles = keptBottles
    }
}

/// Finds everything Kelter leaves in the user's Library: its own folder in
/// Application Support (Wine, graphics layers, bottles, log), caches,
/// URLSession storage, window state and preferences.
public enum KelterRemoval {
    /// Names Kelter's files carry: the bundle identifier, and "Kelter" when
    /// started without a bundle (`swift run`).
    static func names(bundleIdentifier: String?) -> [String] {
        ["Kelter"] + (bundleIdentifier.map { [$0] } ?? [])
    }

    public static func plan(
        paths: AppPaths,
        library: URL,
        bundleIdentifier: String?,
        keepBottles: Bool,
        fileManager: FileManager = .default
    ) -> KelterRemovalPlan {
        var candidates: [URL] = []
        if keepBottles {
            let bottles = paths.bottlesDirectory.standardizedFileURL.lastPathComponent
            let children = (try? fileManager.contentsOfDirectory(atPath: paths.root.path)) ?? []
            candidates += children.sorted().filter { $0 != bottles }
                .map { paths.root.appendingPathComponent($0) }
        } else {
            candidates.append(paths.root)
        }
        for name in names(bundleIdentifier: bundleIdentifier) {
            candidates += [
                library.appendingPathComponent("Caches/\(name)", isDirectory: true),
                library.appendingPathComponent("HTTPStorages/\(name)", isDirectory: true),
                library.appendingPathComponent("HTTPStorages/\(name).binarycookies"),
                library.appendingPathComponent("WebKit/\(name)", isDirectory: true),
                library.appendingPathComponent("Saved Application State/\(name).savedState", isDirectory: true),
                library.appendingPathComponent("Preferences/\(name).plist"),
            ]
        }
        let items = candidates.filter { (try? fileManager.attributesOfItem(atPath: $0.path)) != nil }
        let kept = keepBottles && fileManager.fileExists(atPath: paths.bottlesDirectory.path)
            ? paths.bottlesDirectory : nil
        return KelterRemovalPlan(items: items, keptBottles: kept)
    }

    /// Space a file or folder takes on disk, counting each file once.
    public static func size(of url: URL, fileManager: FileManager = .default) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Deletes the items for good. Missing ones are skipped.
    public static func remove(_ items: [URL], fileManager: FileManager = .default) throws {
        for item in items where (try? fileManager.attributesOfItem(atPath: item.path)) != nil {
            try fileManager.removeItem(at: item)
        }
    }
}
