import AppKit
import KelterCore
import KelterSteam
import SwiftUI

/// The games Steam has installed in a bottle, with their covers.
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    private var games: [SteamApp]? {
        model.steamGames[bottle.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(summary)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Aktualisieren") {
                    model.refreshLibrary(for: bottle)
                }
            }
            if let games, !games.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 160), spacing: 16)],
                          alignment: .leading, spacing: 18) {
                    ForEach(games) { game in
                        GameTile(
                            game: game,
                            cover: model.coverImage(for: game, in: bottle),
                            antiCheat: model.antiCheatHints[bottle.id]?[game.appID],
                            antiCheatMessage: loc(model.config?.antiCheat?.message ?? "")
                        ) {
                            model.play(game, in: bottle)
                        }
                    }
                }
            }
        }
        .onAppear {
            model.refreshLibrary(for: bottle)
        }
    }

    private var summary: String {
        guard let games else { return "Spiele werden gesucht …" }
        switch games.count {
        case 0: return loc("Keine installierten Spiele gefunden. Spiele installierst du in Steam.")
        case 1: return loc("1 installiertes Spiel")
        default: return loc("%@ installierte Spiele", "\(games.count)")
        }
    }
}

private struct GameTile: View {
    let game: SteamApp
    let cover: URL?
    let antiCheat: AntiCheatHint?
    let antiCheatMessage: String
    let play: () -> Void

    @State private var confirmAntiCheat = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            coverView
                .frame(width: 130, height: 195)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            Text(game.name)
                .font(.callout)
                .lineLimit(2, reservesSpace: true)
                .frame(width: 130, alignment: .leading)
            if let antiCheat {
                Label(antiCheat.systems.joined(separator: ", "), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(width: 130, alignment: .leading)
                    .help(loc("%@\n\nGefunden: %@", antiCheatMessage, antiCheat.evidence.joined(separator: "; ")))
            }
            Button(game.isFullyInstalled ? loc("Spielen") : loc("Wird installiert …")) {
                if antiCheat != nil {
                    confirmAntiCheat = true
                } else {
                    play()
                }
            }
            .disabled(!game.isFullyInstalled)
            .frame(width: 130)
        }
        .confirmationDialog(
            loc("%@ nutzt %@", game.name, antiCheat?.systems.joined(separator: ", ") ?? loc("einen Anti-Cheat-Schutz")),
            isPresented: $confirmAntiCheat
        ) {
            Button("Trotzdem starten", action: play)
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(antiCheatMessage)
        }
        .help(game.name + " – " + ByteCountFormatter.string(fromByteCount: game.sizeOnDisk, countStyle: .file))
        .contextMenu {
            Button("Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([game.installURL])
            }
        }
    }

    @ViewBuilder
    private var coverView: some View {
        if let cover, let image = NSImage(contentsOf: cover) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Text(game.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
        }
    }
}
