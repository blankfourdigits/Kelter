import KelterCore
import KelterWine
import SwiftUI

/// Shown until Rosetta 2, Wine and Wine's support package are available.
struct SetupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Einrichtung")
                .font(.title2)
                .bold()

            rosettaRow
            Divider()
            wineRow

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    // MARK: Rosetta

    private var rosettaRow: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon(done: model.rosettaInstalled)
            VStack(alignment: .leading, spacing: 6) {
                Text("Rosetta 2")
                    .font(.headline)
                Text("Wine ist ein Intel-Programm. Rosetta 2 von Apple lässt es auf diesem Mac laufen.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.rosettaInstalled == false {
                    if model.rosettaInstalling {
                        ProgressView("Rosetta 2 wird installiert …")
                            .controlSize(.small)
                    } else {
                        Button("Rosetta 2 installieren") {
                            model.installRosetta()
                        }
                    }
                }
            }
        }
    }

    // MARK: Wine

    private var wineRow: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon(done: model.runtimeInstalled)
            VStack(alignment: .leading, spacing: 6) {
                Text("Wine")
                    .font(.headline)

                if let config = model.config {
                    Text(description(of: config))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let phase = model.installPhase {
                        if let label = model.installLabel {
                            Text(label)
                                .font(.callout)
                        }
                        progress(for: phase)
                    } else if !model.runtimeInstalled {
                        Button("Herunterladen und installieren") {
                            model.installWine()
                        }
                        .disabled(model.rosettaInstalled != true)
                    }
                } else {
                    Text("Die Konfiguration runtimes.json wurde nicht gefunden oder ist fehlerhaft.")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func description(of config: RuntimeConfig) -> String {
        var text = loc("%@, Version %@.", config.wine.name, config.wine.version)
        if let support = config.support {
            text += " " + loc("Dazu kommt %@, Version %@.", support.name, support.version)
        }
        text += " Zusammen sind das rund 250 MB Download und etwa 1 GB auf der Festplatte."
        return text
    }

    @ViewBuilder
    private func progress(for phase: WineInstallPhase) -> some View {
        switch phase {
        case .downloading(let fraction):
            if let fraction {
                ProgressView(value: fraction) {
                    Text(loc("Lade herunter … %@ %%", "\(Int(fraction * 100))"))
                }
                .frame(maxWidth: 360)
            } else {
                ProgressView("Lade herunter …")
                    .controlSize(.small)
            }
        case .verifying:
            ProgressView("Prüfe Prüfsumme …")
                .controlSize(.small)
        case .extracting:
            ProgressView("Entpacke …")
                .controlSize(.small)
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func statusIcon(done: Bool?) -> some View {
        switch done {
        case .some(true):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
        case .some(false):
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.title2)
        case .none:
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
        }
    }
}
