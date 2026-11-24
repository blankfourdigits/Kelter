import KelterCore
import SwiftUI

/// Confirms removing Kelter from the Mac, optionally keeping the bottles.
struct RemoveKelterView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var keepBottles = true
    @State private var removedSize: Int64?
    @State private var bottlesSize: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Kelter vom Mac entfernen?")
                .font(.title3.weight(.semibold))
            Text("Kelter beendet Steam und alle Windows-Programme, löscht Wine, die Grafikschichten, Protokolle und Einstellungen und legt die App in den Papierkorb.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Bottles behalten (Steam, Spiele und Spielstände)", isOn: $keepBottles)
                    Text(keepBottles
                         ? loc("Bleiben im Ordner „Bottles“ liegen (%@). Nach einer Neuinstallation findet Kelter sie wieder.", formatted(bottlesSize))
                         : loc("Alle Bottles werden mit gelöscht (%@), auch Spiele und lokale Spielstände.", formatted(bottlesSize)))
                        .font(.caption)
                        .foregroundStyle(keepBottles ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Text(loc("Wird gelöscht: %@. Das lässt sich nicht rückgängig machen.", formatted(removedSize)))
                .font(.callout)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Kelter entfernen", role: .destructive) {
                    model.removeKelter(keepBottles: keepBottles)
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 500)
        .task(id: keepBottles) { await measure() }
    }

    private func formatted(_ size: Int64?) -> String {
        size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…"
    }

    /// Sizes are added up in the background; bottles with games are large.
    private func measure() async {
        removedSize = nil
        let plan = model.kelterRemovalPlan(keepBottles: keepBottles)
        let bottles = model.paths.bottlesDirectory
        let sizes = await Task.detached {
            (plan.items.reduce(Int64(0)) { $0 + KelterRemoval.size(of: $1) }, KelterRemoval.size(of: bottles))
        }.value
        removedSize = sizes.0
        bottlesSize = sizes.1
    }
}
