import AppKit
import KelterCore
import KelterWine
import SwiftUI
import UniformTypeIdentifiers

/// Asks for consent to a graphics layer's licence (D3DMetal) and where its
/// files should come from: the vendor's own disk image first, a download as
/// the alternative.
struct LayerConsentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let consent: AppModel.LayerConsent
    @State private var agreed = false

    private var layer: RuntimeConfig.GraphicsLayer { consent.layer }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc("%@ einrichten", layer.name))
                .font(.title2)

            if let license = layer.license {
                Text(loc(license.summary))
                    .fixedSize(horizontal: false, vertical: true)
                Link(loc(license.name), destination: license.url)
                Toggle("Ich habe die Lizenz gelesen und stimme ihr zu.", isOn: $agreed)
            }

            Divider()

            if let diskImage = layer.diskImage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Empfohlen: Apples eigenes Paket")
                        .font(.headline)
                    Text("Lade das Paket mit deiner Apple-ID bei Apple herunter. Wähle dann die DMG-Datei oder, wenn sie schon geöffnet ist, das Laufwerk aus.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Link("Zu Apples Download-Seite", destination: diskImage.downloadPage)
                        Spacer()
                        Button("Paket auswählen …") { chooseDiskImage() }
                            .disabled(!agreed)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Alternative: direkt laden")
                    .font(.headline)
                Text(loc("Kelter lädt Apples Dateien aus dem Paket von Gcenx (%@) und prüft die Prüfsumme.", layer.url.host ?? ""))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Direkt laden") { accept(.download) }
                        .disabled(!agreed)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) {
                    model.pendingLayerConsent = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func accept(_ source: LayerSource) {
        model.acceptLayerConsent(consent, source: source)
        dismiss()
    }

    private func chooseDiskImage() {
        let panel = NSOpenPanel()
        panel.title = loc("%@: Apples Paket auswählen", layer.name)
        panel.message = loc("Die DMG-Datei oder das bereits geöffnete Laufwerk auswählen.")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.diskImage, .folder, .volume]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        accept(.diskImage(url))
    }
}
