import Foundation
import SystemConfiguration

/// Replaces personal details in log text with placeholders before the text
/// leaves Kelter (diagnostics folder, "Kopieren" in the log window).
///
/// It only knows patterns and values it was told about, so it can miss
/// things; the diagnostics folder says so. Placeholders are numbered and
/// stay the same across all files of one run (`<steamid-1>` is always the
/// same account), so the logs remain useful for finding faults.
public final class PrivacyRedactor: @unchecked Sendable {
    /// What is known about the person in advance.
    public struct Identity: Sendable, Equatable {
        /// macOS short user name (also the Windows user name in a bottle).
        public var userName: String?
        /// The full name from the macOS account.
        public var fullName: String?
        /// Computer name and local host name.
        public var hostNames: [String]
        /// Steam login names (`AccountName` in `loginusers.vdf`).
        public var steamAccountNames: [String]
        /// Steam display names (`PersonaName`).
        public var steamPersonaNames: [String]
        /// 32-bit Steam account IDs (`userdata/<id>`, or from a SteamID64).
        public var steamAccountIDs: [UInt64]

        public init(
            userName: String? = nil,
            fullName: String? = nil,
            hostNames: [String] = [],
            steamAccountNames: [String] = [],
            steamPersonaNames: [String] = [],
            steamAccountIDs: [UInt64] = []
        ) {
            self.userName = userName
            self.fullName = fullName
            self.hostNames = hostNames
            self.steamAccountNames = steamAccountNames
            self.steamPersonaNames = steamPersonaNames
            self.steamAccountIDs = steamAccountIDs
        }

        /// User name, full name and computer names of this Mac.
        public static func currentMac() -> Identity {
            var hosts: [String] = []
            if let name = SCDynamicStoreCopyComputerName(nil, nil) as String? { hosts.append(name) }
            if let name = SCDynamicStoreCopyLocalHostName(nil) as String? { hosts.append(name) }
            return Identity(userName: NSUserName(), fullName: NSFullUserName(), hostNames: hosts)
        }
    }

    /// Kinds of replaced details, for the summary in `datenschutz.txt`.
    public enum Category: String, CaseIterable, Sendable {
        case steamID = "SteamID"
        case steamAccount = "Steam-Kontonummer"
        case steamLogin = "Steam-Anmeldename"
        case steamPersona = "Steam-Anzeigename"
        case userName = "Benutzername in Pfaden"
        case fullName = "Vollständiger Name"
        case hostName = "Rechnername"
        case lanAddress = "IP-Adresse im eigenen Netz"
        case macAddress = "MAC-Adresse"
        case email = "E-Mail-Adresse"
        case secret = "Sitzungs- oder Token-Kennung"
    }

    /// Steam's offset between a SteamID64 and the 32-bit account ID.
    public static let steamID64Base: UInt64 = 76_561_197_960_265_728

    /// Names shorter than this are not searched for: they would match
    /// ordinary words and destroy useful log text.
    static let minimumNameLength = 3

    private let identity: Identity
    private var accountNumbers: [UInt64: Int] = [:]
    private var lanNumbers: [String: Int] = [:]
    private var loginNumbers: [String: Int] = [:]
    private var personaNumbers: [String: Int] = [:]
    public private(set) var counts: [Category: Int] = [:]
    private let lock = NSLock()

    public init(identity: Identity) {
        self.identity = identity
        for id in identity.steamAccountIDs.sorted() where id != 0 {
            number(forAccount: id)
        }
        for name in identity.steamAccountNames where name.count >= Self.minimumNameLength {
            if loginNumbers[name.lowercased()] == nil { loginNumbers[name.lowercased()] = loginNumbers.count + 1 }
        }
        for name in identity.steamPersonaNames where name.count >= Self.minimumNameLength {
            if personaNumbers[name.lowercased()] == nil { personaNumbers[name.lowercased()] = personaNumbers.count + 1 }
        }
    }

    // MARK: Learning

    /// Notes every Steam account that appears in `text` (as SteamID64 or
    /// `[U:1:n]`), so its bare account number is replaced in all files,
    /// also in those read before.
    public func learn(from text: String) {
        lock.lock()
        defer { lock.unlock() }
        for match in Self.steamID64Pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text), let id = UInt64(text[range]), id > Self.steamID64Base {
                number(forAccount: id - Self.steamID64Base)
            }
        }
        for match in Self.steamID3Pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range(at: 1), in: text), let id = UInt64(text[range]), id != 0 {
                number(forAccount: id)
            }
        }
    }

    @discardableResult
    private func number(forAccount id: UInt64) -> Int {
        if let existing = accountNumbers[id] { return existing }
        let next = accountNumbers.count + 1
        accountNumbers[id] = next
        return next
    }

    // MARK: Redacting

    public func redact(_ text: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        var result = text

        // Secrets first, while their surroundings are still intact.
        result = replace(Self.secretParameterPattern, in: result, category: .secret) { match, text in
            "\(Self.group(1, of: match, in: text))=<redacted>"
        }
        result = replace(Self.jwtPattern, in: result, category: .secret) { _, _ in "JWT <redacted>" }

        // Steam accounts.
        result = replace(Self.steamID64Pattern, in: result, category: .steamID) { match, text in
            guard let id = UInt64(Self.group(0, of: match, in: text)), id > Self.steamID64Base else {
                return Self.group(0, of: match, in: text)
            }
            return "<steamid-\(self.number(forAccount: id - Self.steamID64Base))>"
        }
        result = replace(Self.steamID3Pattern, in: result, category: .steamAccount) { match, text in
            let id = UInt64(Self.group(1, of: match, in: text)) ?? 0
            if id == 0 { return Self.group(0, of: match, in: text) }
            return "[U:1:<account-\(self.number(forAccount: id))>]"
        }
        for (id, number) in accountNumbers.sorted(by: { $0.value < $1.value }) {
            let pattern = Self.regex("(?<![0-9])\(id)(?![0-9])")
            result = replace(pattern, in: result, category: .steamAccount) { _, _ in "<account-\(number)>" }
        }

        // Names. Longer ones first, so a name inside another is not cut.
        for (name, number) in loginNumbers.sorted(by: { $0.key.count > $1.key.count }) {
            result = replaceWord(name, in: result, with: "<steam-login-\(number)>", category: .steamLogin)
        }
        for (name, number) in personaNumbers.sorted(by: { $0.key.count > $1.key.count }) {
            result = replaceWord(name, in: result, with: "<steam-name-\(number)>", category: .steamPersona)
        }
        if let fullName = identity.fullName, fullName.count >= Self.minimumNameLength,
           fullName.caseInsensitiveCompare(identity.userName ?? "") != .orderedSame {
            result = replaceWord(fullName, in: result, with: "<full-name>", category: .fullName)
        }
        for host in hostVariants() {
            result = replaceWord(host, in: result, with: "<host>", category: .hostName)
        }
        if let user = identity.userName, !user.isEmpty {
            // Only inside paths: a short user name like "max" is an
            // ordinary word elsewhere.
            let pattern = Self.regex(
                "(?i)(users(?:\\\\{1,4}|/))\(NSRegularExpression.escapedPattern(for: user))(?=$|[\\\\/\\s\"'`:;,)\\]>])"
            )
            result = replace(pattern, in: result, category: .userName) { match, text in
                "\(Self.group(1, of: match, in: text))<user>"
            }
        }

        // Network and contact details.
        result = replace(Self.ipv4Pattern, in: result, category: .lanAddress) { match, text in
            let address = Self.group(0, of: match, in: text)
            guard Self.isPrivateAddress(address) else { return address }
            if let existing = self.lanNumbers[address] { return "<lan-ip-\(existing)>" }
            let next = self.lanNumbers.count + 1
            self.lanNumbers[address] = next
            return "<lan-ip-\(next)>"
        }
        result = replace(Self.macAddressPattern, in: result, category: .macAddress) { _, _ in "<mac-address>" }
        result = replace(Self.emailPattern, in: result, category: .email) { _, _ in "<email>" }
        return result
    }

    /// Computer names as they appear: as set, with dashes (Steam writes
    /// `macbook-pro-von-…`), URL-encoded, and with `.local`.
    private func hostVariants() -> [String] {
        var variants: Set<String> = []
        for host in identity.hostNames where host.count >= Self.minimumNameLength {
            variants.insert(host)
            let dashed = host.lowercased()
                .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
                .joined()
            variants.insert(dashed)
            variants.insert(host.replacingOccurrences(of: " ", with: "%20"))
            variants.insert(host.replacingOccurrences(of: " ", with: "+"))
        }
        // ".local" is matched with the plain name; the suffix stays.
        return variants.sorted { $0.count > $1.count }
    }

    private func replaceWord(_ word: String, in text: String, with placeholder: String, category: Category) -> String {
        let pattern = Self.regex("(?i)(?<![\\p{L}\\p{N}_])\(NSRegularExpression.escapedPattern(for: word))(?![\\p{L}\\p{N}_])")
        return replace(pattern, in: text, category: category) { _, _ in placeholder }
    }

    private func replace(
        _ pattern: NSRegularExpression,
        in text: String,
        category: Category,
        with make: (NSTextCheckingResult, String) -> String
    ) -> String {
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }
        var result = ""
        var last = text.startIndex
        var replaced = 0
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let original = String(text[range])
            let replacement = make(match, text)
            result += text[last..<range.lowerBound]
            result += replacement
            if replacement != original { replaced += 1 }
            last = range.upperBound
        }
        result += text[last...]
        if replaced > 0 { counts[category, default: 0] += replaced }
        return result
    }

    // MARK: Patterns

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed or escaped, so they always compile.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }

    private static func group(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String {
        guard let range = Range(match.range(at: index), in: text) else { return "" }
        return String(text[range])
    }

    static let steamID64Pattern = regex("(?<![0-9])7656119[0-9]{10}(?![0-9])")
    static let steamID3Pattern = regex("\\[U:1:([0-9]+)\\]")
    static let jwtPattern = regex("JWT [0-9]{6,}")
    static let secretParameterPattern = regex(
        "(?i)\\b(sessionid|access_token|refresh_token|webapi_token|auth_token|authtoken|token|steamLoginSecure|password)=([^&\\s\"';<>]+)"
    )
    static let ipv4Pattern = regex("(?<![0-9.])(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?![0-9]|\\.[0-9])")
    static let macAddressPattern = regex("(?i)(?<![0-9a-f:])(?:[0-9a-f]{2}:){5}[0-9a-f]{2}(?![0-9a-f:])")
    static let emailPattern = regex("(?i)[a-z0-9._%+-]+@[a-z0-9-]+(?:\\.[a-z0-9-]+)*\\.[a-z]{2,}")

    /// Addresses only reachable inside the home network: 10/8, 172.16/12,
    /// 192.168/16 and link-local 169.254/16. Loopback, 0.0.0.0 and public
    /// server addresses stay, they matter for connection faults.
    static func isPrivateAddress(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    // MARK: Kelter's own log lines

    /// Writes paths inside the home folder as `~/…`.
    public static func abbreviatingHome(_ text: String, home: String) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard home.count > 1, text.contains(home) else { return text }
        let pattern = regex("\(NSRegularExpression.escapedPattern(for: home))(?=$|[/\\s\"'`:;,)\\]])")
        let range = NSRange(text.startIndex..., in: text)
        return pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "~")
    }
}
