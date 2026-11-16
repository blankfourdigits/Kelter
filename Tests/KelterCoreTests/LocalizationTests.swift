import Foundation
import XCTest
@testable import KelterCore

/// Every text Kelter shows must have an English translation in
/// Resources/en.lproj/Localizable.strings. The texts are found in the
/// sources the same way SwiftUI and `loc(…)` look them up: fixed strings in
/// SwiftUI views, every `loc("…")`, and the texts from runtimes.json that
/// are shown.
final class LocalizationTests: XCTestCase {
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // KelterCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
    }

    private func englishStrings() throws -> [String: String] {
        let url = packageRoot.appendingPathComponent("Resources/en.lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }

    private static let literal = #""((?:[^"\\]|\\.)*)""#
    private static let viewText = try! NSRegularExpression(pattern:
        #"\b(?:Text|Button|Label|Toggle|Picker|TextField|Section|GroupBox|LabeledContent|Menu|ProgressView|DisclosureGroup|Link)\(\s*"#
            + literal)
    private static let modifierText = try! NSRegularExpression(pattern:
        #"\.(?:help|navigationTitle|alert|confirmationDialog)\(\s*"# + literal + #"|prompt:\s*"# + literal)
    private static let locText = try! NSRegularExpression(pattern: #"\bloc\(\s*"# + literal)
    private static let choiceText = try! NSRegularExpression(pattern: #" [?:] "# + literal)

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Texts with fewer than three letters in a row ("·", "%@ – %@") need no
    /// translation.
    private static func needsTranslation(_ text: String) -> Bool {
        text.range(of: "[A-Za-zÄÖÜäöüß]{3}", options: .regularExpression) != nil
    }

    private struct Found {
        var keys: [String: String] = [:]   // text → where
        var problems: [String] = []
    }

    private func textsInSources() throws -> Found {
        var found = Found()
        let sources = packageRoot.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(atPath: sources.path)?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") }
            .sorted() ?? []
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for (expression, isView) in [(Self.viewText, true), (Self.modifierText, true), (Self.locText, false)] {
                for match in expression.matches(in: text, range: range) {
                    guard let group = (1..<match.numberOfRanges).first(where: { match.range(at: $0).location != NSNotFound }),
                          let groupRange = Range(match.range(at: group), in: text)
                    else { continue }
                    let raw = String(text[groupRange])
                    let line = text[..<groupRange.lowerBound].filter { $0 == "\n" }.count + 1
                    if isView && raw.contains("\\(") {
                        found.problems.append("\(file):\(line): Platzhalter im Oberflächen-Text, bitte loc(…) nutzen: \(raw)")
                        continue
                    }
                    let key = Self.unescape(raw)
                    if Self.needsTranslation(key), found.keys[key] == nil {
                        found.keys[key] = "\(file):\(line)"
                    }
                }
            }
            // `cond ? "Text" : "Text"` gives plain strings that SwiftUI shows
            // untranslated; they have to go through loc(…). Symbol names and
            // the diagnostics notes (German like the log) are exempt.
            for match in Self.choiceText.matches(in: text, range: range) {
                guard let groupRange = Range(match.range(at: 1), in: text) else { continue }
                let raw = String(text[groupRange])
                let lineRange = text.lineRange(for: groupRange)
                let wholeLine = text[lineRange]
                if wholeLine.contains("systemImage") || wholeLine.contains("notes.append")
                    || wholeLine.contains("log.append") { continue }
                if Self.needsTranslation(raw) && file.hasPrefix("KelterApp/") {
                    let line = text[..<groupRange.lowerBound].filter { $0 == "\n" }.count + 1
                    found.problems.append("\(file):\(line): Text in einer Kurzform ohne loc(…): \(raw)")
                }
            }
        }
        return found
    }

    private func shownConfigTexts() throws -> [String] {
        let config = try RuntimeConfig.load(from: packageRoot.appendingPathComponent("Resources/runtimes.json"))
        var texts: [String] = []
        for layer in config.graphicsLayers ?? [] {
            if let license = layer.license { texts += [license.name, license.summary] }
            if let paused = layer.paused { texts.append(paused) }
        }
        if let message = config.antiCheat?.message { texts.append(message) }
        for verb in config.winetricks?.verbs ?? [] { texts += [verb.name, verb.description] }
        texts += config.steam.argumentPresets.map(\.name)
        return texts.filter(Self.needsTranslation)
    }

    func testEveryShownTextHasAnEnglishTranslation() throws {
        let english = try englishStrings()
        let found = try textsInSources()
        XCTAssertEqual(found.problems, [], found.problems.joined(separator: "\n"))
        XCTAssertGreaterThan(found.keys.count, 150, "the scan finds the texts")

        let missing = found.keys.filter { english[$0.key] == nil }
            .map { "\($0.value): \($0.key)" }
            .sorted()
        XCTAssertEqual(missing, [], "Ohne englische Übersetzung:\n" + missing.joined(separator: "\n"))

        let missingConfig = try shownConfigTexts().filter { english[$0] == nil }
        XCTAssertEqual(missingConfig, [], "Texte aus runtimes.json ohne Übersetzung")
    }

    func testTranslationsKeepTheirPlaceholders() throws {
        let placeholder = try NSRegularExpression(pattern: "%(?:@|%)")
        func placeholders(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }
        }
        for (german, english) in try englishStrings() {
            XCTAssertFalse(english.isEmpty, german)
            XCTAssertEqual(placeholders(german), placeholders(english), german)
        }
    }

    func testLocFallsBackToGermanAndFillsPlaceholders() {
        // Tests run without Kelter's app bundle: the German key is used.
        XCTAssertEqual(loc("Steam wird beendet …"), "Steam wird beendet …")
        XCTAssertEqual(loc("Lade herunter … %@ %%", "42"), "Lade herunter … 42 %")
        XCTAssertEqual(loc("%@ nutzt %@", "Spiel", "BattlEye"), "Spiel nutzt BattlEye")
    }

    func testLanguageChoiceSetsMacOSLanguageForNextStart() throws {
        let suite = "KelterLanguage-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppLanguage.current(defaults: defaults), .system)
        AppLanguage.english.apply(to: defaults)
        XCTAssertEqual(AppLanguage.current(defaults: defaults), .english)
        XCTAssertEqual(defaults.stringArray(forKey: AppLanguage.appleLanguagesKey), ["en"])
        AppLanguage.system.apply(to: defaults)
        XCTAssertEqual(AppLanguage.current(defaults: defaults), .system)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[AppLanguage.appleLanguagesKey])
    }
}
