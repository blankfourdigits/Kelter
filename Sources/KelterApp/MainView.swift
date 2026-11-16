import AppKit
import KelterCore
import KelterSteam
import KelterWine
import SwiftUI
import UniformTypeIdentifiers

/// The everyday window: bottles on the left, the selected bottle's games on
/// the right. Technical settings live in the bottle's settings sheet.
struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showNewBottle = false
    @State private var newBottleName = ""

    var body: some View {
        if !model.isReady {
            WelcomeView()
        } else {
            NavigationSplitView {
                List(selection: $model.selectedBottleID) {
                    Section("Bottles") {
                        ForEach(model.bottles) { bottle in
                            BottleRow(bottle: bottle)
                                .tag(bottle.id)
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 190, ideal: 220)
                .safeAreaInset(edge: .bottom) {
                    Button {
                        newBottleName = ""
                        showNewBottle = true
                    } label: {
                        Label("Neue Bottle", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .disabled(model.busyMessage != nil)
                }
            } detail: {
                if let bottle = model.selectedBottle {
                    BottleHomeView(bottle: bottle)
                        .id(bottle.id)
                } else {
                    noBottle
                }
            }
            .navigationTitle("Kelter")
            .alert("Neue Bottle", isPresented: $showNewBottle) {
                TextField("Name", text: $newBottleName)
                Button("Anlegen") {
                    model.createBottle(named: newBottleName)
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Eine Bottle ist eine eigene, abgeschlossene Windows-Umgebung.")
            }
        }
    }

    private var noBottle: some View {
        ContentUnavailableView {
            Label("Willkommen bei Kelter", systemImage: "gamecontroller")
        } description: {
            Text("Kelter richtet Steam für Windows-Spiele ein: eine Bottle, der Steam-Installer von Valve, fertig.")
        } actions: {
            if let message = model.busyMessage {
                ProgressView(message)
                    .controlSize(.small)
            } else {
                Button("Steam einrichten") {
                    model.setUpSteam()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}

private struct BottleRow: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    var body: some View {
        HStack {
            Label(bottle.name, systemImage: model.isSteamInstalled(in: bottle) ? "gamecontroller" : "shippingbox")
            Spacer()
            if model.isRunning(bottle) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .help("Läuft")
            }
        }
    }
}

// MARK: Bottle

/// One bottle: its state, Steam, and the installed games as covers.
struct BottleHomeView: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    @State private var search = ""
    @State private var showSettings = false
    @State private var dropTargeted = false

    private var steamInstalled: Bool { model.isSteamInstalled(in: bottle) }
    private var running: Bool { model.isRunning(bottle) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if !steamInstalled {
                    noSteam
                } else {
                    games
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Spiele suchen")
        .toolbar {
            ToolbarItem(placement: .status) {
                if let message = model.busyMessage {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(message).lineLimit(1)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            ToolbarItem {
                if steamInstalled {
                    if running {
                        Button {
                            model.quitSteam(in: bottle)
                        } label: {
                            Label("Steam beenden", systemImage: "xmark.circle")
                        }
                        .labelStyle(.titleAndIcon)
                        .help("Beendet Steam und alle Spiele dieser Bottle.")
                    } else {
                        Button {
                            model.launchSteam(in: bottle)
                        } label: {
                            Label("Steam-Client öffnen", systemImage: "macwindow")
                        }
                        .labelStyle(.titleAndIcon)
                        .help("Öffnet nur das Steam-Fenster, ohne ein Spiel zu starten. Ein Spiel startest du mit einem Klick auf sein Cover.")
                    }
                }
            }
            ToolbarItem {
                Button {
                    showSettings = true
                } label: {
                    Label("Einstellungen", systemImage: "gearshape")
                }
                .help("Einstellungen dieser Bottle")
            }
        }
        .disabled(model.busyMessage != nil)
        .sheet(isPresented: $showSettings) {
            BottleSettingsView(bottle: model.bottles.first { $0.id == bottle.id } ?? bottle)
                .environmentObject(model)
        }
        .onAppear { model.refreshLibrary(for: bottle) }
        .onChange(of: running) { model.refreshLibrary(for: bottle) }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard model.busyMessage == nil,
                  let file = urls.first(where: { ["exe", "msi"].contains($0.pathExtension.lowercased()) })
            else { return false }
            model.runFile(file, in: bottle)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bottle.name)
                .font(.largeTitle.weight(.semibold))
            HStack(spacing: 6) {
                Circle()
                    .fill(running ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(statusText)
                Text("·").foregroundStyle(.tertiary)
                Text(loc("Grafik: %@", bottle.settings.graphicsBackend.shortName))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if !steamInstalled { return running ? loc("Läuft") : loc("Bereit") }
        return running ? loc("Steam läuft") : loc("Steam ist aus")
    }

    private var noSteam: some View {
        ContentUnavailableView {
            Label("Steam ist hier noch nicht installiert", systemImage: "gamecontroller")
        } description: {
            Text("Kelter lädt den Installer von Valve und richtet Steam in dieser Bottle ein. Andere Windows-Programme kannst du auch einfach auf dieses Fenster ziehen.")
        } actions: {
            Button("Steam installieren") {
                model.installSteam(in: bottle)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    @ViewBuilder
    private var games: some View {
        let all = model.steamGames[bottle.id]
        let shown = SteamLibrary.filter(all ?? [], matching: search)
        if all == nil {
            ProgressView("Spiele werden gesucht …")
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if all?.isEmpty == true {
            ContentUnavailableView {
                Label("Noch keine Spiele", systemImage: "square.grid.2x2")
            } description: {
                Text("Installiere Spiele in Steam. Sie erscheinen hier von selbst.")
            } actions: {
                if !running {
                    Button("Steam-Client öffnen") { model.launchSteam(in: bottle) }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if shown.isEmpty {
            ContentUnavailableView.search(text: search)
                .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 22)],
                      alignment: .leading, spacing: 26) {
                ForEach(shown) { game in
                    GameCard(
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
}

// MARK: Game card

/// A cover that shows a play button on hover; a click plays.
struct GameCard: View {
    let game: SteamApp
    let cover: URL?
    let antiCheat: AntiCheatHint?
    let antiCheatMessage: String
    let play: () -> Void

    @State private var hovering = false
    @State private var confirmAntiCheat = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                coverImage
                if hovering && game.isFullyInstalled {
                    Color.black.opacity(0.35)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                }
                if let antiCheat {
                    VStack {
                        HStack {
                            Label("Anti-Cheat", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.orange, in: Capsule())
                                .foregroundStyle(.white)
                                .help(antiCheat.systems.joined(separator: ", ") + ": " + antiCheatMessage)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            .shadow(color: .black.opacity(hovering ? 0.3 : 0.15), radius: hovering ? 10 : 4, y: hovering ? 6 : 2)
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
            .onTapGesture(perform: start)

            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(game.isFullyInstalled
                     ? ByteCountFormatter.string(fromByteCount: game.sizeOnDisk, countStyle: .file)
                     : loc("Wird installiert …"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Spielen", action: start)
                .disabled(!game.isFullyInstalled)
            Button("Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([game.installURL])
            }
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
    }

    private func start() {
        guard game.isFullyInstalled else { return }
        if antiCheat != nil {
            confirmAntiCheat = true
        } else {
            play()
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let cover, let image = NSImage(contentsOf: cover) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(colors: [Color(red: 0.36, green: 0.10, blue: 0.24), Color(red: 0.16, green: 0.05, blue: 0.15)],
                               startPoint: .top, endPoint: .bottom)
                Text(game.name)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(12)
            }
        }
    }
}

extension GraphicsBackendKind {
    /// Short name for status lines.
    var shortName: String {
        switch self {
        case .wined3d: return loc("Wine (OpenGL)")
        case .dxmt: return loc("DXMT")
        case .d3dmetal: return loc("D3DMetal")
        case .dxvk: return loc("DXVK")
        }
    }
}
