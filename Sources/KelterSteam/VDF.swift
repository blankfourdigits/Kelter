import Foundation
import KelterCore

/// Valve's text KeyValues format (VDF), as used by `appmanifest_*.acf`,
/// `libraryfolders.vdf` and `config.vdf`:
///
///     "AppState"
///     {
///         "appid"     "220"
///         "name"      "Half-Life 2"
///     }
///
/// Keys are compared without regard to case, as Steam does. A key may occur
/// more than once; `[$WIN32]`-style conditions and `//` comments are skipped.
public indirect enum VDFValue: Equatable, Sendable {
    case string(String)
    case object([(key: String, value: VDFValue)])

    public static func == (lhs: VDFValue, rhs: VDFValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)):
            return a == b
        case (.object(let a), .object(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default:
            return false
        }
    }

    /// The first value under `key`, ignoring case.
    public subscript(key: String) -> VDFValue? {
        guard case .object(let entries) = self else { return nil }
        return entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    /// The text of a string value.
    public var string: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// The entries of an object, in file order.
    public var entries: [(key: String, value: VDFValue)] {
        if case .object(let entries) = self { return entries }
        return []
    }
}

public enum VDFError: LocalizedError, Equatable {
    case unexpectedEnd
    case unexpectedToken(String, line: Int)

    public var errorDescription: String? {
        switch self {
        case .unexpectedEnd:
            return loc("Die Steam-Datei endet unerwartet.")
        case .unexpectedToken(let token, let line):
            return loc("Unerwartetes Zeichen \"%@\" in Zeile %@ der Steam-Datei.", "\(token)", "\(line)")
        }
    }
}

public enum VDF {
    /// Parses a whole file. The result is an object with the top-level
    /// entries, usually one (`"AppState" { … }`).
    public static func parse(_ text: String) throws -> VDFValue {
        var parser = Parser(text)
        let entries = try parser.entries(topLevel: true)
        return .object(entries)
    }

    public static func parse(contentsOf url: URL) throws -> VDFValue {
        // Steam writes UTF-8; fall back to Latin-1 for odd older files.
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return try parse(text)
    }

    private enum Token: Equatable {
        case text(String)
        case open
        case close
    }

    private struct Parser {
        private let scalars: [Unicode.Scalar]
        private var index = 0
        private var line = 1

        init(_ text: String) {
            scalars = Array(text.unicodeScalars)
        }

        mutating func entries(topLevel: Bool) throws -> [(key: String, value: VDFValue)] {
            var result: [(key: String, value: VDFValue)] = []
            while true {
                guard let token = try nextToken() else {
                    if topLevel { return result }
                    throw VDFError.unexpectedEnd
                }
                switch token {
                case .close:
                    if topLevel { throw VDFError.unexpectedToken("}", line: line) }
                    return result
                case .open:
                    throw VDFError.unexpectedToken("{", line: line)
                case .text(let key):
                    guard let next = try nextToken() else { throw VDFError.unexpectedEnd }
                    switch next {
                    case .text(let value):
                        result.append((key, .string(value)))
                    case .open:
                        result.append((key, .object(try entries(topLevel: false))))
                    case .close:
                        throw VDFError.unexpectedToken("}", line: line)
                    }
                }
            }
        }

        private mutating func nextToken() throws -> Token? {
            while index < scalars.count {
                let c = scalars[index]
                switch c {
                case "\n":
                    line += 1
                    index += 1
                case " ", "\t", "\r", "\u{FEFF}":
                    index += 1
                case "/" where peek(1) == "/":
                    while index < scalars.count, scalars[index] != "\n" { index += 1 }
                case "[":
                    // Platform condition such as [$WIN32]: not needed here.
                    while index < scalars.count, scalars[index] != "]" { index += 1 }
                    index += 1
                case "{":
                    index += 1
                    return .open
                case "}":
                    index += 1
                    return .close
                case "\"":
                    index += 1
                    return .text(try quoted())
                default:
                    return .text(unquoted())
                }
            }
            return nil
        }

        private func peek(_ offset: Int) -> Unicode.Scalar? {
            index + offset < scalars.count ? scalars[index + offset] : nil
        }

        private mutating func quoted() throws -> String {
            var text = String.UnicodeScalarView()
            while index < scalars.count {
                let c = scalars[index]
                index += 1
                switch c {
                case "\"":
                    return String(text)
                case "\\":
                    guard index < scalars.count else { throw VDFError.unexpectedEnd }
                    let escaped = scalars[index]
                    index += 1
                    switch escaped {
                    case "n": text.append("\n")
                    case "t": text.append("\t")
                    default: text.append(escaped)   // \\ and \"
                    }
                case "\n":
                    line += 1
                    text.append(c)
                default:
                    text.append(c)
                }
            }
            throw VDFError.unexpectedEnd
        }

        private mutating func unquoted() -> String {
            var text = String.UnicodeScalarView()
            while index < scalars.count {
                let c = scalars[index]
                if c == " " || c == "\t" || c == "\r" || c == "\n" || c == "{" || c == "}" || c == "\"" { break }
                text.append(c)
                index += 1
            }
            return String(text)
        }
    }
}
