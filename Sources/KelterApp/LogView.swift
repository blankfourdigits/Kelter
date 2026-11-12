import AppKit
import SwiftUI

/// Live view of the log file: everything Kelter and Wine print.
struct LogView: View {
    @EnvironmentObject private var model: AppModel

    private static let bottomID = "log-bottom"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Log")
                    .font(.headline)
                Spacer()
                Button("Kopieren") {
                    model.copyLogToClipboard()
                }
                .disabled(model.logText.isEmpty)
                Button("Leeren") {
                    model.clearLogView()
                }
                .disabled(model.logText.isEmpty)
                Button("Logdatei zeigen") {
                    model.revealLogFile()
                }
                Button("Diagnose sammeln …") {
                    chooseDiagnosticsFolder()
                }
                .help("Legt Log, Einstellungen, Steam-Logs und die Liste der laufenden Wine-Prozesse in einen Ordner deiner Wahl.")
            }
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.logText.isEmpty ? "Noch keine Ausgabe." : model.logText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(model.logText.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomID)
                    }
                }
                .onChange(of: model.logText) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func chooseDiagnosticsFolder() {
        let panel = NSOpenPanel()
        panel.title = "Ordner für die Diagnose wählen"
        panel.message = "Kelter legt darin einen neuen Ordner \"Kelter-Diagnose-…\" an. Steams Logs können deinen Kontonamen enthalten."
        panel.prompt = "Hier sammeln"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let last = model.lastDiagnosticsParent {
            panel.directoryURL = last
        }
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        model.collectDiagnostics(into: folder)
    }
}
