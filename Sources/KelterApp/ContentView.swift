import KelterCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showNewBottle = false
    @State private var newBottleName = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedBottleID) {
                Section("Bottles") {
                    ForEach(model.bottles) { bottle in
                        Label(bottle.name, systemImage: "shippingbox")
                            .tag(bottle.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItem {
                    Button {
                        model.setUpSteam()
                    } label: {
                        Label("Steam einrichten", systemImage: "gamecontroller")
                    }
                    .disabled(!model.isReady || model.busyMessage != nil)
                    .help("Steam einrichten und starten")
                }
                ToolbarItem {
                    Button {
                        newBottleName = ""
                        showNewBottle = true
                    } label: {
                        Label("Neue Bottle", systemImage: "plus")
                    }
                    .disabled(!model.isReady || model.busyMessage != nil)
                    .help("Neue Bottle anlegen")
                }
            }
        } detail: {
            VSplitView {
                mainArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .frame(minHeight: 240)
                LogView()
                    .frame(minHeight: 120, idealHeight: 200)
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
        .sheet(item: $model.pendingLayerConsent) { consent in
            LayerConsentView(consent: consent)
                .environmentObject(model)
        }
        .alert("Fehler", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task {
            await model.start()
        }
    }

    @ViewBuilder
    private var mainArea: some View {
        if !model.isReady {
            SetupView()
        } else if let bottle = model.selectedBottle {
            BottleDetailView(bottle: bottle)
                // A fresh view per bottle, so dialogs of one bottle never
                // act on another.
                .id(bottle.id)
        } else {
            VStack(spacing: 12) {
                Text("Noch keine Bottle")
                    .font(.title2)
                if let message = model.busyMessage {
                    ProgressView(message)
                        .controlSize(.small)
                } else {
                    Button("Steam einrichten") {
                        model.setUpSteam()
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    Text("Legt eine Bottle namens Steam an, installiert Steam darin und startet es. Für andere Programme legst du mit dem Plus-Knopf eine leere Bottle an.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { presented in
                if !presented { model.errorMessage = nil }
            }
        )
    }
}
