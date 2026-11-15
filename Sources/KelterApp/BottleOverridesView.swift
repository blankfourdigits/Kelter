import KelterCore
import SwiftUI

/// Editors for a bottle's own environment variables and DLL overrides.
/// They apply to every Wine program of the bottle, Steam and its games
/// included, from their next start.
struct BottleOverridesView: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    @State private var newVariable = ""
    @State private var newValue = ""
    @State private var newLibrary = ""
    @State private var newMode: DllOverrideMode = .nativeThenBuiltin

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gilt für alle Programme der Bottle, auch Steam und Spiele, ab ihrem nächsten Start.")
                .font(.callout)
                .foregroundStyle(.secondary)

            environmentEditor
            Divider()
            overridesEditor
        }
    }

    // MARK: Environment

    private var environmentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Umgebungsvariablen")
                .font(.headline)
            let entries = SettingsEditing.sorted(bottle.settings.environment)
            if entries.isEmpty {
                Text("Keine eigenen Variablen.")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries, id: \.key) { entry in
                HStack {
                    Text(entry.key)
                        .font(.body.monospaced())
                        .frame(width: 200, alignment: .leading)
                        .textSelection(.enabled)
                    Text(entry.value.isEmpty ? "(leer)" : entry.value)
                        .font(.body.monospaced())
                        .foregroundStyle(entry.value.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        newVariable = entry.key
                        newValue = entry.value
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Zum Ändern unten übernehmen")
                    Button(role: .destructive) {
                        model.updateSettings(of: bottle) { $0.environment.removeValue(forKey: entry.key) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Entfernen")
                }
            }
            HStack {
                TextField("Name, z. B. DXVK_HUD", text: $newVariable)
                    .font(.body.monospaced())
                    .frame(width: 200)
                TextField("Wert", text: $newValue)
                    .font(.body.monospaced())
                    .onSubmit(addVariable)
                Button("Setzen", action: addVariable)
                    .disabled(newVariable.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addVariable() {
        let name = newVariable
        let value = newValue
        if model.editSettings(of: bottle, { try SettingsEditing.setVariable(name, value: value, in: &$0) }) {
            newVariable = ""
            newValue = ""
        }
    }

    // MARK: DLL overrides

    private var overridesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DLL-Overrides")
                .font(.headline)
            Text("Legt fest, ob Wine für eine Bibliothek seine eigene Version oder eine mitgelieferte Windows-Version lädt.")
                .font(.callout)
                .foregroundStyle(.secondary)
            let entries = SettingsEditing.sorted(bottle.settings.dllOverrides)
            if entries.isEmpty {
                Text("Keine eigenen Overrides.")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries, id: \.key) { entry in
                HStack {
                    Text(entry.key)
                        .font(.body.monospaced())
                        .frame(width: 200, alignment: .leading)
                        .textSelection(.enabled)
                    Picker("", selection: modeBinding(for: entry.key, value: entry.value)) {
                        ForEach(DllOverrideMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300)
                    Spacer()
                    Button(role: .destructive) {
                        model.updateSettings(of: bottle) { $0.dllOverrides.removeValue(forKey: entry.key) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Entfernen")
                }
            }
            HStack {
                TextField("Bibliothek, z. B. d3d11", text: $newLibrary)
                    .font(.body.monospaced())
                    .frame(width: 200)
                    .onSubmit(addOverride)
                Picker("", selection: $newMode) {
                    ForEach(DllOverrideMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 300)
                Button("Hinzufügen", action: addOverride)
                    .disabled(newLibrary.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func modeBinding(for library: String, value: String) -> Binding<DllOverrideMode> {
        Binding(
            get: { DllOverrideMode(wineValue: value) ?? .nativeThenBuiltin },
            set: { mode in
                model.updateSettings(of: bottle) { $0.dllOverrides[library] = mode.rawValue }
            }
        )
    }

    private func addOverride() {
        let library = newLibrary
        let mode = newMode
        if model.editSettings(of: bottle, { try SettingsEditing.setOverride(library, mode: mode, in: &$0) }) {
            newLibrary = ""
        }
    }
}
