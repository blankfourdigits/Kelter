import KelterCore
import KelterWine
import SwiftUI

/// Installs Winetricks packages into a bottle: the common ones with one
/// click, others by name.
struct WinetricksView: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    @State private var otherVerbs = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Installiert Windows-Laufzeitbibliotheken und Schriften, die manche Spiele brauchen. Steam vorher beenden ist am sichersten.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let verbs = model.config?.winetricks?.verbs {
                ForEach(verbs, id: \.verb) { verb in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc(verb.name))
                            Text(verb.verb + " – " + loc(verb.description))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Installieren") {
                            model.runWinetricks([verb.verb], in: bottle)
                        }
                    }
                }
            }
            HStack {
                TextField("Weitere Pakete, z. B. dotnet48 physx", text: $otherVerbs)
                    .font(.body.monospaced())
                    .onSubmit(installOthers)
                Button("Installieren", action: installOthers)
                    .disabled(otherVerbs.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func installOthers() {
        do {
            let verbs = try Winetricks.verbs(fromText: otherVerbs)
            model.runWinetricks(verbs, in: bottle)
            otherVerbs = ""
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
