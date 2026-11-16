import AppKit
import KelterCore
import KelterWine
import SwiftUI

/// First start: what Kelter needs before the first bottle (Rosetta 2, Wine),
/// as numbered steps. The test view keeps the plain `SetupView`.
struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                VStack(spacing: 8) {
                    Text("Willkommen bei Kelter")
                        .font(.largeTitle.weight(.semibold))
                    Text("Windows-Spiele aus deiner Steam-Bibliothek auf dem Mac. Zwei Dinge richtet Kelter vorher ein, danach Steam.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                VStack(spacing: 0) {
                    StepRow(
                        number: 1,
                        title: "Rosetta 2",
                        text: loc("Von Apple. Lässt Wine, ein Intel-Programm, auf diesem Mac laufen."),
                        state: rosettaState
                    ) {
                        Button("Installieren") { model.installRosetta() }
                            .buttonStyle(.borderedProminent)
                    }
                    Divider().padding(.leading, 64)
                    StepRow(
                        number: 2,
                        title: "Wine",
                        text: wineText,
                        state: wineState
                    ) {
                        Button("Laden") { model.installWine() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.rosettaInstalled != true)
                    }
                    Divider().padding(.leading, 64)
                    StepRow(
                        number: 3,
                        title: "Steam",
                        text: loc("Danach legt Kelter mit einem Klick eine Bottle an und installiert Steam darin."),
                        state: .later
                    ) { EmptyView() }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: 580)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))

                if model.config == nil {
                    Label("Die Konfiguration runtimes.json fehlt oder ist fehlerhaft.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .padding(48)
            .frame(maxWidth: .infinity)
        }
    }

    private var rosettaState: StepState {
        switch model.rosettaInstalled {
        case .some(true): return .done
        case .none: return .checking
        case .some(false): return model.rosettaInstalling ? .working(loc("Wird installiert …"), nil) : .todo
        }
    }

    private var wineState: StepState {
        if model.runtimeInstalled { return .done }
        if let phase = model.installPhase {
            switch phase {
            case .downloading(let fraction):
                return .working(fraction.map { loc("Lade … %@ %%", "\(Int($0 * 100))") } ?? loc("Lade …"), fraction)
            case .verifying:
                return .working(loc("Prüfe …"), nil)
            case .extracting:
                return .working(loc("Entpacke …"), nil)
            }
        }
        return .todo
    }

    private var wineText: String {
        guard let config = model.config else { return "Die Windows-Umgebung, in der Steam läuft." }
        return loc("%@ %@. Rund 250 MB Download, etwa 1 GB auf der Festplatte.", "\(config.wine.name)", "\(config.wine.version)")
    }
}

private enum StepState {
    case todo
    case checking
    case working(String, Double?)
    case done
    case later
}

private struct StepRow<Action: View>: View {
    let number: Int
    let title: String
    let text: String
    let state: StepState
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 32, height: 32)
                if case .done = state {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text(verbatim: "\(number)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .working(let label, let fraction) = state {
                    if let fraction {
                        ProgressView(value: fraction) { Text(label).font(.caption) }
                            .padding(.top, 4)
                    } else {
                        ProgressView { Text(label).font(.caption) }
                            .progressViewStyle(.linear)
                            .padding(.top, 4)
                    }
                }
            }
            Spacer(minLength: 12)
            switch state {
            case .todo:
                action()
            case .checking:
                ProgressView().controlSize(.small)
            case .done:
                Text("Fertig")
                    .font(.callout)
                    .foregroundStyle(.green)
            case .working, .later:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .opacity(isLater ? 0.6 : 1)
    }

    private var isActive: Bool {
        switch state {
        case .todo, .working: return true
        default: return false
        }
    }

    private var isLater: Bool {
        if case .later = state { return true }
        return false
    }

    private var badgeColor: Color {
        switch state {
        case .done: return .green
        case .todo, .working: return .accentColor
        case .checking, .later: return Color.secondary.opacity(0.2)
        }
    }
}
