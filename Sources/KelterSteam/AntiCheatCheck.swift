import Foundation
import KelterCore

/// Why Kelter thinks a game uses an anti-cheat that does not run under Wine.
public struct AntiCheatHint: Equatable, Sendable {
    /// The anti-cheat systems found, e.g. "BattlEye".
    public var systems: [String]
    /// What was found: the game's id is on the list, or files in its folder.
    public var evidence: [String]

    public init(systems: [String], evidence: [String]) {
        self.systems = systems
        self.evidence = evidence
    }
}

/// Looks for kernel anti-cheat in an installed game, from the lists in
/// runtimes.json: known Steam app ids and typical files or folders in the
/// game's folder (checked at the top and one level below).
public enum AntiCheatCheck {
    public static func hint(
        for game: SteamApp,
        config: RuntimeConfig.AntiCheat,
        fileManager: FileManager = .default
    ) -> AntiCheatHint? {
        var systems: [String] = []
        var evidence: [String] = []
        func add(_ system: String, _ reason: String) {
            if !systems.contains(system) { systems.append(system) }
            evidence.append(reason)
        }

        if let known = config.knownApps.first(where: { $0.appID == game.appID }) {
            add(known.system, "Spiel-ID \(game.appID) steht auf der Liste")
        }

        let markers = Dictionary(
            config.markers.map { ($0.name.lowercased(), $0.system) },
            uniquingKeysWith: { first, _ in first }
        )
        if !markers.isEmpty {
            let folder = game.installURL
            let top = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            var candidates = top.map { ($0, $0) }
            for name in top.sorted() {
                var isDirectory: ObjCBool = false
                let sub = folder.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: sub.path, isDirectory: &isDirectory), isDirectory.boolValue,
                      let inner = try? fileManager.contentsOfDirectory(atPath: sub.path)
                else { continue }
                candidates += inner.map { ($0, "\(name)/\($0)") }
            }
            for (name, path) in candidates.sorted(by: { $0.1 < $1.1 }) {
                if let system = markers[name.lowercased()] {
                    add(system, "\(path) im Spielordner")
                }
            }
        }

        return systems.isEmpty ? nil : AntiCheatHint(systems: systems, evidence: evidence)
    }
}
