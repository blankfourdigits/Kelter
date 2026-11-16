import AppKit
import KelterCore
import SwiftUI

/// Kelter's own settings (Kelter → Einstellungen …): the app language.
struct AppSettingsView: View {
    @State private var language = AppLanguage.current()
    @State private var changed = false

    var body: some View {
        Form {
            Picker("Sprache", selection: $language) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .onChange(of: language) { _, newValue in
                newValue.apply()
                changed = true
            }

            if changed {
                HStack {
                    Text("Gilt nach einem Neustart von Kelter.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if Self.canRelaunch {
                        Button("Jetzt neu starten", action: Self.relaunch)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }

    /// Only an app bundle can start itself again; `swift run` cannot.
    private static var canRelaunch: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// Opens a new copy of the app as soon as this one has quit.
    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                             Bundle.main.bundlePath, "\(ProcessInfo.processInfo.processIdentifier)"]
        try? process.run()
        NSApp.terminate(nil)
    }
}
