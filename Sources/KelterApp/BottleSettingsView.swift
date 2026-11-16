import AppKit
import KelterCore
import SwiftUI
import UniformTypeIdentifiers

/// Everything about a bottle that is not about playing, in tabs.
struct BottleSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralSettings(bottle: bottle, close: { dismiss() })
                    .tabItem { Label("Allgemein", systemImage: "gearshape") }
                GraphicsSettings(bottle: bottle)
                    .tabItem { Label("Grafik", systemImage: "display") }
                ScrollView {
                    WinetricksView(bottle: bottle)
                        .padding(20)
                }
                .tabItem { Label("Winetricks", systemImage: "shippingbox") }
                AdvancedSettings(bottle: bottle)
                    .tabItem { Label("Erweitert", systemImage: "slider.horizontal.3") }
            }
            .padding([.top, .horizontal], 16)

            HStack {
                if let message = model.busyMessage {
                    ProgressView().controlSize(.small)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 560)
    }
}

// MARK: General

private struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle
    let close: () -> Void

    @State private var name = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .onSubmit(rename)
                Picker("Windows-Version", selection: model.settingBinding(bottle, \.windowsVersion)) {
                    ForEach(WindowsVersion.allCases, id: \.self) { version in
                        Text(version.displayName).tag(version)
                    }
                }
            }
            Section("Programme") {
                LabeledContent("Windows-Programm") {
                    Button("Starten …", action: chooseProgram)
                }
                LabeledContent("Wine-Konfiguration") {
                    Button("Öffnen") { model.runWineTool("winecfg", in: bottle) }
                }
                LabeledContent("Ordner der Bottle") {
                    Button("Im Finder zeigen") { model.revealInFinder(bottle) }
                }
            }
            Section {
                LabeledContent("Alles in dieser Bottle löschen") {
                    Button("Bottle löschen …", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { name = bottle.name }
        .onDisappear(perform: rename)
        .confirmationDialog(loc("Bottle „%@“ wirklich löschen?", bottle.name), isPresented: $confirmDelete) {
            Button("Endgültig löschen", role: .destructive) {
                close()
                model.deleteBottle(bottle)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle darin installierten Programme, Spiele und Spielstände gehen verloren. Das lässt sich nicht rückgängig machen.")
        }
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != (model.bottles.first { $0.id == bottle.id }?.name ?? bottle.name) else { return }
        model.renameBottle(bottle, to: trimmed)
    }

    private func chooseProgram() {
        let panel = NSOpenPanel()
        panel.title = loc("Windows-Programm auswählen")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["exe", "msi"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let file = panel.url else { return }
        model.runFile(file, in: bottle)
    }
}

// MARK: Graphics

private struct GraphicsSettings: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    private var current: Bottle { model.bottles.first { $0.id == bottle.id } ?? bottle }

    private var choices: [GraphicsBackendKind] {
        var choices = model.availableGraphicsBackends
        if !choices.contains(current.settings.graphicsBackend) {
            choices.append(current.settings.graphicsBackend)
        }
        return choices
    }

    var body: some View {
        Form {
            Section {
                Picker("Grafik", selection: Binding(
                    get: { current.settings.graphicsBackend },
                    set: { model.setGraphicsBackend($0, for: current) }
                )) {
                    ForEach(choices, id: \.self) { backend in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.config?.pauseReason(for: backend) == nil
                                 ? backend.displayName : loc("%@ – pausiert", backend.displayName))
                            Text(backend.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(backend)
                    }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Gilt ab dem nächsten Start von Steam.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("FPS-Anzeige einblenden", isOn: model.settingBinding(bottle, \.metalHUD))
                Toggle("Retina-Modus (schärfer, aber langsamer)", isOn: model.settingBinding(bottle, \.retinaMode))
                if model.supportsMSync {
                    Toggle("MSync (schnellere Synchronisation)", isOn: model.settingBinding(bottle, \.msync))
                }
            } footer: {
                Text("Die FPS-Anzeige von Metal funktioniert mit DXMT, nicht mit Wines eigener Grafik.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

extension GraphicsBackendKind {
    /// One line in everyday words for the graphics settings.
    var explanation: String {
        switch self {
        case .wined3d: return loc("Läuft mit allem, aber langsamer. Für alte Spiele (DirectX 9).")
        case .dxmt: return loc("Schnell für DirectX 10 und 11. DirectX 9 läuft weiter über Wine. Empfohlen.")
        case .d3dmetal: return loc("Apples Übersetzung für DirectX 12. Zurzeit nicht nutzbar.")
        case .dxvk: return loc("DirectX 10 und 11 über Vulkan.")
        }
    }
}

// MARK: Advanced

private struct AdvancedSettings: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    @State private var steamArguments = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.isSteamInstalled(in: bottle) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Startparameter für Steam")
                            .font(.headline)
                        HStack {
                            TextField("Startparameter", text: $steamArguments)
                                .font(.body.monospaced())
                                .onSubmit(saveArguments)
                            Menu("Vorschläge") {
                                ForEach(Array(model.steamArgumentPresets.enumerated()), id: \.offset) { _, preset in
                                    Button(loc(preset.name)) {
                                        model.setSteamArguments(preset.arguments, for: bottle)
                                        steamArguments = CommandLineArguments.join(preset.arguments)
                                    }
                                }
                                Divider()
                                Button("Standard") {
                                    model.setSteamArguments(nil, for: bottle)
                                    steamArguments = CommandLineArguments.join(model.config?.steam.defaultArguments ?? [])
                                }
                            }
                            .fixedSize()
                        }
                        Text("Startparameter für einzelne Spiele setzt du in Steam: Rechtsklick aufs Spiel → Eigenschaften.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }

                BottleOverridesView(bottle: bottle)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Fehlersuche")
                        .font(.headline)
                    Toggle("Ausführliches Wine-Log", isOn: model.settingBinding(bottle, \.verboseLogging))
                    HStack {
                        Button("Wine-Prozesse beenden") { model.stopWine(in: bottle) }
                        Button("Registrierungseditor") { model.runWineTool("regedit", in: bottle) }
                    }
                    Text("Log, Diagnose und alle Schalter auf einer Seite: Menü Darstellung → Testansicht (⌥⌘T).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { steamArguments = model.steamArgumentsText(for: bottle) }
        .onDisappear(perform: saveArguments)
    }

    private func saveArguments() {
        let typed = CommandLineArguments.split(steamArguments)
        if typed != CommandLineArguments.split(model.steamArgumentsText(for: bottle)) {
            model.setSteamArguments(typed, for: bottle)
        }
    }
}
