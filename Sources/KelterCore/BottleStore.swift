import Foundation

public enum BottleStoreError: LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)
    case notFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Der Name darf nicht leer sein."
        case .duplicateName(let name):
            return "Es gibt bereits eine Bottle mit dem Namen \"\(name)\"."
        case .notFound:
            return "Diese Bottle wurde nicht gefunden."
        }
    }
}

/// Creates, lists, renames and deletes bottles on disk.
///
/// Layout below `directory`:
///
///     <uuid>/bottle.json   name, creation date, settings
///     <uuid>/prefix/       the Wine prefix (WINEPREFIX)
///
/// The folder is named after the id, not the bottle name, so renaming never
/// moves a prefix and names may contain any character.
public final class BottleStore {
    public let directory: URL
    private let fileManager: FileManager

    private static let metadataFileName = "bottle.json"

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    // MARK: Locations

    public func directory(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func prefixURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("prefix", isDirectory: true)
    }

    private func metadataURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent(Self.metadataFileName)
    }

    // MARK: Reading

    /// All bottles, oldest first. Folders without a readable `bottle.json` are
    /// ignored rather than treated as an error.
    public func list() throws -> [Bottle] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var bottles: [Bottle] = []
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent),
                  let bottle = try? read(id),
                  bottle.id == id
            else { continue }
            bottles.append(bottle)
        }
        return bottles.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func bottle(id: UUID) throws -> Bottle {
        guard fileManager.fileExists(atPath: metadataURL(for: id).path) else {
            throw BottleStoreError.notFound(id)
        }
        return try read(id)
    }

    // MARK: Writing

    @discardableResult
    public func create(name: String, settings: BottleSettings = BottleSettings()) throws -> Bottle {
        let cleanName = try validatedName(name, excluding: nil)
        // Whole seconds only: that is what survives the ISO 8601 round trip,
        // so the returned value equals what `list()` reads back.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let bottle = Bottle(id: UUID(), name: cleanName, createdAt: now, settings: settings)
        try fileManager.createDirectory(at: prefixURL(for: bottle.id), withIntermediateDirectories: true)
        try write(bottle)
        return bottle
    }

    @discardableResult
    public func rename(_ id: UUID, to newName: String) throws -> Bottle {
        var bottle = try self.bottle(id: id)
        bottle.name = try validatedName(newName, excluding: id)
        try write(bottle)
        return bottle
    }

    /// Saves changed settings (or a changed name) of an existing bottle.
    public func update(_ bottle: Bottle) throws {
        guard fileManager.fileExists(atPath: metadataURL(for: bottle.id).path) else {
            throw BottleStoreError.notFound(bottle.id)
        }
        var updated = bottle
        updated.name = try validatedName(bottle.name, excluding: bottle.id)
        try write(updated)
    }

    /// Removes the bottle including its whole Wine prefix. Not undoable.
    public func delete(_ id: UUID) throws {
        let folder = directory(for: id)
        guard fileManager.fileExists(atPath: folder.path) else {
            throw BottleStoreError.notFound(id)
        }
        try fileManager.removeItem(at: folder)
    }

    // MARK: Helpers

    private func validatedName(_ name: String, excluding id: UUID?) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw BottleStoreError.emptyName }
        let taken = try list().contains { other in
            other.id != id && other.name.compare(clean, options: [.caseInsensitive]) == .orderedSame
        }
        guard !taken else { throw BottleStoreError.duplicateName(clean) }
        return clean
    }

    private func read(_ id: UUID) throws -> Bottle {
        let data = try Data(contentsOf: metadataURL(for: id))
        return try Self.makeDecoder().decode(Bottle.self, from: data)
    }

    private func write(_ bottle: Bottle) throws {
        try fileManager.createDirectory(at: directory(for: bottle.id), withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(bottle)
        try data.write(to: metadataURL(for: bottle.id), options: [.atomic])
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
