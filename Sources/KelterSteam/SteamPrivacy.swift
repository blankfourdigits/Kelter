import Foundation
import KelterCore

/// Reads which Steam accounts a bottle knows, so their names and numbers can
/// be taken out of logs before they are passed on.
public enum SteamPrivacy {
    /// Adds the accounts of the Steam installation in `steamDirectory` to
    /// `identity`: login and display names from `config/loginusers.vdf`,
    /// account numbers from those SteamIDs and from `userdata/<id>`.
    public static func identity(
        adding steamDirectory: URL,
        to identity: PrivacyRedactor.Identity,
        fileManager: FileManager = .default
    ) -> PrivacyRedactor.Identity {
        var result = identity
        var ids = Set(identity.steamAccountIDs)

        let loginUsers = steamDirectory.appendingPathComponent("config/loginusers.vdf")
        if let root = try? VDF.parse(contentsOf: loginUsers), let users = root["users"] {
            for (key, value) in users.entries {
                if let steamID = UInt64(key), steamID > PrivacyRedactor.steamID64Base {
                    ids.insert(steamID - PrivacyRedactor.steamID64Base)
                }
                if let name = value["AccountName"]?.string, !name.isEmpty,
                   !result.steamAccountNames.contains(name) {
                    result.steamAccountNames.append(name)
                }
                if let name = value["PersonaName"]?.string, !name.isEmpty,
                   !result.steamPersonaNames.contains(name) {
                    result.steamPersonaNames.append(name)
                }
            }
        }

        let userdata = steamDirectory.appendingPathComponent("userdata", isDirectory: true)
        for folder in (try? fileManager.contentsOfDirectory(atPath: userdata.path)) ?? [] {
            if let id = UInt64(folder), id != 0 { ids.insert(id) }
        }
        result.steamAccountIDs = ids.sorted()
        return result
    }
}
