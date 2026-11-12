import AppKit
import KelterCore
import SwiftUI
import UniformTypeIdentifiers

struct BottleDetailView: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDelete = false
    @State private var dropTargeted = false
    @State private var steamArgumentsText = ""
    @State private var steamBrowserArgumentsText = ""

    private var isBusy: Bool {
        model.busyMessage != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let message = model.busyMessage {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Steam") {
                    steamSection
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }

                GroupBox("Programme") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("Programm starten …") {
                                chooseFile()
                            }
                            Button("Wine-Prozesse beenden") {
                                model.stopWine(in: bottle)
                            }
                        }
                        Text("Eine .exe- oder .msi-Datei kannst du auch auf dieses Fenster ziehen.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("Einstellungen") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Windows-Version", selection: windowsVersion) {
                            ForEach(WindowsVersion.allCases, id: \.self) { version in
                                Text(version.displayName).tag(version)
                            }
                        }
                        .frame(maxWidth: 320)

                        Picker("Grafik", selection: graphicsBackend) {
                            ForEach(model.availableGraphicsBackends, id: \.self) { backend in
                                Text(backend.displayName).tag(backend)
                            }
                        }
                        .frame(maxWidth: 420)
                        Text("Gilt ab dem nächsten Start von Steam. DXMT übersetzt DirectX 10 und 11 nach Metal und wird bei der ersten Auswahl geladen (rund 20 MB). DirectX 9 läuft immer über Wines eingebaute Grafik.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if model.supportsMSync {
                            Toggle("MSync (schnellere Synchronisation, gilt ab dem nächsten Start)", isOn: msync)
                        }
                        Toggle("Retina-Modus (schärfer, aber langsamer)", isOn: retinaMode)
                        Toggle("FPS-Anzeige von Metal einblenden (nur mit DXMT oder D3DMetal)", isOn: metalHUD)
                        Toggle("Ausführliches Wine-Log (zur Fehlersuche, gilt ab dem nächsten Start)", isOn: verboseLogging)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("Werkzeuge") {
                    HStack {
                        Button("Wine-Konfiguration") {
                            model.runWineTool("winecfg", in: bottle)
                        }
                        Button("Registrierungseditor") {
                            model.runWineTool("regedit", in: bottle)
                        }
                        Button("Im Finder zeigen") {
                            model.revealInFinder(bottle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
            }
            .padding(24)
            .disabled(isBusy)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !isBusy, let file = urls.first(where: Self.isWindowsFile) else { return false }
            model.runFile(file, in: bottle)
            return true
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
        .onAppear {
            steamArgumentsText = model.steamArgumentsText(for: bottle)
            steamBrowserArgumentsText = model.steamBrowserArgumentsText(for: bottle)
        }
        .alert("Bottle umbenennen", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Umbenennen") {
                model.renameBottle(bottle, to: renameText)
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(
            "Bottle \"\(bottle.name)\" wirklich löschen?",
            isPresented: $showDelete
        ) {
            Button("Endgültig löschen", role: .destructive) {
                model.deleteBottle(bottle)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle darin installierten Programme, Spiele und Spielstände gehen verloren. Das lässt sich nicht rückgängig machen.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(bottle.name)
                .font(.title)
                .bold()
            Spacer()
            Button("Umbenennen …") {
                renameText = bottle.name
                showRename = true
            }
            Button("Löschen …", role: .destructive) {
                showDelete = true
            }
        }
    }

    // MARK: Steam

    @ViewBuilder
    private var steamSection: some View {
        if model.isSteamInstalled(in: bottle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Steam starten") {
                        saveSteamArguments()
                        model.launchSteam(in: bottle)
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Steam beenden") {
                        model.quitSteam(in: bottle)
                    }
                }

                HStack {
                    TextField("Startparameter", text: $steamArgumentsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            saveSteamArguments()
                        }
                    Menu("Vorschläge") {
                        ForEach(Array(model.steamArgumentPresets.enumerated()), id: \.offset) { _, preset in
                            Button(preset.name) {
                                steamArgumentsText = CommandLineArguments.join(preset.arguments)
                                model.setSteamArguments(preset.arguments, for: bottle)
                            }
                        }
                        Divider()
                        Button("Standard aus runtimes.json") {
                            model.setSteamArguments(nil, for: bottle)
                            steamArgumentsText = CommandLineArguments.join(model.config?.steam.defaultArguments ?? [])
                        }
                    }
                    .fixedSize()
                }

                if model.steamUIFixEnabled {
                    HStack {
                        TextField("Browser-Parameter", text: $steamBrowserArgumentsText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit {
                                saveSteamArguments()
                            }
                        Button("Standard") {
                            model.setSteamBrowserArguments(nil, for: bottle)
                            steamBrowserArgumentsText = CommandLineArguments.join(
                                model.config?.steam.uiFix.browserArguments ?? []
                            )
                        }
                    }
                }

                Text("Oben stehen die Startparameter für Steam, darunter die Parameter, die Kelters Hilfsbibliothek an Steams eingebauten Browser weitergibt. Änderungen gelten ab dem nächsten Start von Steam.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Button("Steam in dieser Bottle installieren") {
                    model.installSteam(in: bottle)
                }
                Text("Lädt den Windows-Installer von Valve und richtet Steam ein.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Stores what is typed in the two parameter fields, if it differs from
    /// what the bottle already uses.
    private func saveSteamArguments() {
        let typed = CommandLineArguments.split(steamArgumentsText)
        let current = CommandLineArguments.split(model.steamArgumentsText(for: bottle))
        if typed != current {
            model.setSteamArguments(typed, for: bottle)
        }

        guard model.steamUIFixEnabled else { return }
        let typedBrowser = CommandLineArguments.split(steamBrowserArgumentsText)
        let currentBrowser = CommandLineArguments.split(model.steamBrowserArgumentsText(for: bottle))
        if typedBrowser != currentBrowser {
            // Read the bottle again: the line above may just have changed it.
            let latest = model.bottles.first { $0.id == bottle.id } ?? bottle
            model.setSteamBrowserArguments(typedBrowser, for: latest)
        }
    }

    // MARK: Settings bindings

    private var windowsVersion: Binding<WindowsVersion> {
        Binding(
            get: { bottle.settings.windowsVersion },
            set: { newValue in
                model.updateSettings(of: bottle) { $0.windowsVersion = newValue }
            }
        )
    }

    private var retinaMode: Binding<Bool> {
        Binding(
            get: { bottle.settings.retinaMode },
            set: { newValue in
                model.updateSettings(of: bottle) { $0.retinaMode = newValue }
            }
        )
    }

    private var graphicsBackend: Binding<GraphicsBackendKind> {
        Binding(
            get: { bottle.settings.graphicsBackend },
            set: { newValue in
                model.setGraphicsBackend(newValue, for: bottle)
            }
        )
    }

    private var msync: Binding<Bool> {
        Binding(
            get: { bottle.settings.msync },
            set: { newValue in
                model.updateSettings(of: bottle) { $0.msync = newValue }
            }
        )
    }

    private var verboseLogging: Binding<Bool> {
        Binding(
            get: { bottle.settings.verboseLogging },
            set: { newValue in
                model.updateSettings(of: bottle) { $0.verboseLogging = newValue }
            }
        )
    }

    private var metalHUD: Binding<Bool> {
        Binding(
            get: { bottle.settings.metalHUD },
            set: { newValue in
                model.updateSettings(of: bottle) { $0.metalHUD = newValue }
            }
        )
    }

    // MARK: Files

    private static func isWindowsFile(_ url: URL) -> Bool {
        ["exe", "msi"].contains(url.pathExtension.lowercased())
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Windows-Programm auswählen"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["exe", "msi"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let file = panel.url else { return }
        model.runFile(file, in: bottle)
    }
}
