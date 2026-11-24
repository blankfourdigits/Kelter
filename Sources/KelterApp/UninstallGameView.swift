import KelterCore
import KelterSteam
import SwiftUI

/// Confirms uninstalling a game and asks whether its local saves go too.
struct UninstallGameView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let game: SteamApp
    let bottle: Bottle

    @State private var deleteSaves = false
    @State private var plan: Result<SteamUninstallPlan, Error>?

    private var canUninstall: Bool {
        if case .success = plan { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc("„%@“ deinstallieren?", game.name))
                .font(.title3.weight(.semibold))
            Text(loc("Löscht das Spiel (%@) endgültig aus dieser Bottle. Steams eigene Deinstallation wird dabei übersprungen, weil sie bei manchen Spielen unter Wine hängen bleibt.",
                     ByteCountFormatter.string(fromByteCount: game.sizeOnDisk, countStyle: .file)))
                .fixedSize(horizontal: false, vertical: true)
            if model.isRunning(bottle) {
                Label("Steam wird dafür beendet.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }

            switch plan {
            case .success(let plan):
                savesSection(plan.saveFolders)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case nil:
                ProgressView()
                    .controlSize(.small)
            }

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Endgültig deinstallieren", role: .destructive) {
                    model.uninstall(game, in: bottle, deleteSaves: deleteSaves)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canUninstall)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { plan = model.uninstallPlan(for: game, in: bottle) }
    }

    @ViewBuilder
    private func savesSection(_ folders: [URL]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if folders.isEmpty {
                    Text("Keine lokalen Spielstände gefunden.")
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Lokale Spielstände ebenfalls löschen", isOn: $deleteSaves)
                    ForEach(folders, id: \.self) { folder in
                        Text(displayPath(folder))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                Text("Spielstände in der Steam-Cloud bleiben erhalten und kommen bei einer Neuinstallation zurück.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    /// The folder below the bottle's `drive_c` as a Windows-like path,
    /// otherwise with `~` for the home folder.
    private func displayPath(_ url: URL) -> String {
        let path = url.path
        if let range = path.range(of: "/drive_c/") {
            return "C:\\" + path[range.upperBound...].replacingOccurrences(of: "/", with: "\\")
        }
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
