import AppKit
import Foundation
import KelterCore
import KelterSteam
import KelterWine
import SwiftUI

/// State of the whole app. Views only call methods here; all file and Wine
/// work goes through KelterCore and KelterWine.
@MainActor
final class AppModel: ObservableObject {
    // MARK: Published state

    @Published private(set) var bottles: [Bottle] = []
    @Published var selectedBottleID: UUID?

    /// `nil` while the check is still running.
    @Published private(set) var rosettaInstalled: Bool?
    @Published private(set) var rosettaInstalling = false

    @Published private(set) var config: RuntimeConfig?
    @Published private(set) var configSource: URL?
    @Published private(set) var wineInstallation: WineInstallation?
    /// Run-time libraries and renderers that belong to the Wine build, if
    /// runtimes.json names such a package.
    @Published private(set) var supportInstallation: SupportInstallation?
    /// Copies of Wine with a graphics layer built in, by graphics choice.
    @Published private(set) var wineVariants: [GraphicsBackendKind: WineInstallation] = [:]
    /// What is being downloaded right now ("Wine …", "Laufzeitbibliotheken …").
    @Published private(set) var installLabel: String?
    /// Non-nil while Wine is being downloaded and unpacked.
    @Published private(set) var installPhase: WineInstallPhase?

    /// Text for a long running operation such as creating a bottle.
    @Published private(set) var busyMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var logText = ""
    /// A graphics layer with licence terms (D3DMetal) waiting for the
    /// user's consent and choice of source.
    @Published var pendingLayerConsent: LayerConsent?

    struct LayerConsent: Identifiable {
        let backend: GraphicsBackendKind
        let bottleID: Bottle.ID
        let layer: RuntimeConfig.GraphicsLayer
        var id: String { "\(bottleID)-\(backend.rawValue)" }
    }

    // MARK: Dependencies

    let paths: AppPaths
    let log: LogFile
    private let store: BottleStore
    private let tailer: LogTailer
    private var logTimer: Timer?
    private var started = false
    private var wineInstallRunning = false

    private static let maxLogCharacters = 120_000

    init() {
        let paths = AppPaths.standard()
        self.paths = paths
        self.log = LogFile(url: paths.logFile)
        self.store = BottleStore(directory: paths.bottlesDirectory)
        self.tailer = LogTailer(url: paths.logFile)
    }

    // MARK: Derived state

    var isReady: Bool {
        rosettaInstalled == true && runtimeInstalled
    }

    /// Wine and, if the configuration names one, its support package.
    var runtimeInstalled: Bool {
        guard let config, wineInstallation != nil else { return false }
        return config.support == nil || supportInstallation != nil
    }

    /// The Direct3D choices that can work with what is installed.
    var availableGraphicsBackends: [GraphicsBackendKind] {
        GraphicsBackendKind.allCases.filter { backend in
            if backend == .wined3d { return true }
            if config?.pauseReason(for: backend) != nil { return false }
            // Either a layer that Kelter builds into a copy of Wine …
            if config?.graphicsLayer(for: backend) != nil { return true }
            // … or renderers that come with the Wine build's support package.
            guard let supportInstallation else { return false }
            return backend.rendererIDs.allSatisfy { supportInstallation.renderer(id: $0) != nil }
        }
    }

    /// Changes a bottle's graphics choice. If the choice needs a layer that
    /// is not installed yet, it is downloaded and built first.
    func setGraphicsBackend(_ backend: GraphicsBackendKind, for bottle: Bottle) {
        guard let config, let wineInstallation, busyMessage == nil else { return }
        if let reason = config.pauseReason(for: backend) {
            errorMessage = reason
            return
        }
        guard let layer = config.graphicsLayer(for: backend), wineVariants[backend] == nil else {
            updateSettings(of: bottle) { $0.graphicsBackend = backend }
            return
        }
        // A layer under licence terms is fetched only after the user agreed
        // and chose where it comes from.
        if layer.license != nil, !WineVariantInstaller.hasLayerFiles(paths: paths, layer: layer) {
            pendingLayerConsent = LayerConsent(backend: backend, bottleID: bottle.id, layer: layer)
            return
        }
        Task {
            do {
                try await self.installVariant(for: backend, base: wineInstallation, config: config)
                self.updateSettings(of: bottle) { $0.graphicsBackend = backend }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// The user agreed to the layer's licence and picked a source.
    func acceptLayerConsent(_ consent: LayerConsent, source: LayerSource) {
        pendingLayerConsent = nil
        guard let config, let wineInstallation, busyMessage == nil else { return }
        log.append("\nZustimmung zur \(consent.layer.license?.name ?? "Lizenz") von \(consent.layer.name) erteilt.\n")
        Task {
            do {
                try await self.installVariant(
                    for: consent.backend, base: wineInstallation, config: config, source: source)
                if let bottle = self.bottles.first(where: { $0.id == consent.bottleID }) {
                    self.updateSettings(of: bottle) { $0.graphicsBackend = consent.backend }
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Fetches a graphics layer if needed and builds the copy of Wine with it.
    private func installVariant(
        for backend: GraphicsBackendKind,
        base: WineInstallation,
        config: RuntimeConfig,
        source: LayerSource? = nil
    ) async throws {
        guard let layer = config.graphicsLayer(for: backend) else { return }
        busyMessage = "\(layer.name) \(layer.version) wird geladen und eingerichtet …"
        defer { busyMessage = nil }
        let installer = WineVariantInstaller(
            paths: paths, wine: config.wine, layer: layer, patches: config.winePatches, log: log)
        wineVariants[backend] = try await installer.install(base: base, source: source) { _ in }
    }

    var supportsMSync: Bool {
        config?.wine.supportsMSync ?? false
    }

    var selectedBottle: Bottle? {
        guard let selectedBottleID else { return nil }
        return bottles.first { $0.id == selectedBottleID }
    }

    private var runner: WineRunner? {
        guard let config, let wineInstallation else { return nil }
        return WineRunner(
            installation: wineInstallation,
            config: config.wine,
            support: supportInstallation,
            variants: wineVariants,
            log: log
        )
    }

    // MARK: Start-up

    func start() async {
        guard !started else { return }
        started = true

        do {
            try paths.ensureDirectories()
            try log.prepare()
        } catch {
            errorMessage = "Der Datenordner konnte nicht angelegt werden: \(error.localizedDescription)"
        }

        // Show only this session in the log pane.
        tailer.skipToEnd()
        log.append("\n=== Kelter gestartet: \(Date().formatted(date: .abbreviated, time: .standard)) ===\n")
        logTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollLog()
            }
        }

        loadConfig()
        refreshBottles()
        await refreshEnvironment()
    }

    private func loadConfig() {
        do {
            let loaded = try RuntimeConfig.loadFirst(candidates: configCandidates())
            config = loaded.config
            configSource = loaded.source
            log.append("Konfiguration: \(loaded.source.path)\n")
        } catch {
            config = nil
            configSource = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Where `runtimes.json` is looked for, most specific first.
    private func configCandidates() -> [URL] {
        [paths.userRuntimeConfig] + AppModel.resourceDirectories().map { $0.appendingPathComponent("runtimes.json") }
    }

    /// Folders that may hold Kelter's resources (runtimes.json, the Steam
    /// helper library), most specific first.
    private static func resourceDirectories() -> [URL] {
        var directories: [URL] = []
        // Inside Kelter.app (built with scripts/make-app.sh).
        if let bundled = Bundle.main.resourceURL {
            directories.append(bundled)
        }
        // `swift run` from the package folder.
        directories.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources", isDirectory: true)
        )
        // Development builds started from elsewhere (for example by Xcode):
        // the package folder this source file was compiled from.
        directories.append(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // KelterApp
                .deletingLastPathComponent() // Sources
                .deletingLastPathComponent() // package root
                .appendingPathComponent("Resources", isDirectory: true)
        )
        return directories
    }

    /// The first resources folder that contains `relativePath`.
    private static func resourceDirectory(containing relativePath: String) -> URL? {
        resourceDirectories().first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(relativePath).path)
        }
    }

    func refreshEnvironment() async {
        if let config {
            wineInstallation = WineInstallation.locate(paths: paths, config: config.wine)
            supportInstallation = config.support.flatMap { SupportInstallation.locate(paths: paths, config: $0) }
            var variants: [GraphicsBackendKind: WineInstallation] = [:]
            for backend in GraphicsBackendKind.allCases {
                if let layer = config.graphicsLayer(for: backend),
                   let variant = WineVariantInstaller.locate(
                       paths: paths, wine: config.wine, layer: layer, patches: config.winePatches) {
                    variants[backend] = variant
                }
            }
            wineVariants = variants
        } else {
            wineInstallation = nil
            supportInstallation = nil
            wineVariants = [:]
        }
        let installed = await Task.detached { Rosetta.isInstalled() }.value
        rosettaInstalled = installed
    }

    // MARK: Log

    private func pollLog() {
        let new = tailer.readNew()
        guard !new.isEmpty else { return }
        var text = logText + new
        if text.count > Self.maxLogCharacters {
            text = String(text.suffix(Self.maxLogCharacters))
        }
        logText = text
    }

    func copyLogToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logText, forType: .string)
    }

    func clearLogView() {
        logText = ""
    }

    func revealLogFile() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.logFile])
    }

    // MARK: Diagnostics

    private static let diagnosticsFolderKey = "diagnosticsFolder"

    /// Where the last diagnostics folder was saved, as a starting point for
    /// the folder dialog.
    var lastDiagnosticsParent: URL? {
        guard let path = UserDefaults.standard.string(forKey: AppModel.diagnosticsFolderKey) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Collects logs, settings and the process list for the selected bottle
    /// into a new folder inside `parent` and shows it in the Finder.
    func collectDiagnostics(into parent: URL) {
        UserDefaults.standard.set(parent.path, forKey: AppModel.diagnosticsFolderKey)

        let bottle = selectedBottle
        var notes: [String] = []
        if let config {
            notes.append("Wine: \(config.wine.name) \(config.wine.version)")
            notes.append("Wine installiert: \(wineInstallation != nil ? "ja" : "nein")")
            if let support = config.support {
                notes.append("Zusatzpaket: \(support.name) \(support.version), installiert: \(supportInstallation != nil ? "ja" : "nein")")
            }
            notes.append("Steam-Fensterkorrektur: \(config.steam.uiFix.enabled ? "an" : "aus")")
        }
        if let configSource {
            notes.append("Konfiguration: \(configSource.path)")
        }
        var steamDirectory: URL?
        if let bottle {
            notes.append("Bottle: \(bottle.name) (\(bottle.id.uuidString))")
            notes.append("Windows-Version: \(bottle.settings.windowsVersion.rawValue)")
            notes.append("Grafik: \(bottle.settings.graphicsBackend.rawValue)")
            notes.append("MSync: \(bottle.settings.msync ? "an" : "aus")")
            notes.append("Ausführliches Wine-Log: \(bottle.settings.verboseLogging ? "an" : "aus")")
            if let config {
                let prefix = store.prefixURL(for: bottle.id)
                notes.append("Steam-Startparameter: \(steamArgumentsText(for: bottle))")
                notes.append("Browser-Parameter: \(steamBrowserArgumentsText(for: bottle))")
                if SteamLocation.isInstalled(prefix: prefix, config: config.steam) {
                    steamDirectory = SteamLocation.directory(prefix: prefix, config: config.steam)
                }
            }
        }
        let input = DiagnosticsCollector.Input(
            logFile: paths.logFile,
            runtimeConfig: configSource,
            bottleDirectory: bottle.map { store.directory(for: $0.id) },
            steamDirectory: steamDirectory,
            notes: notes
        )
        let log = self.log
        Task {
            do {
                let folder = try await Task.detached {
                    try DiagnosticsCollector().collect(input, into: parent)
                }.value
                log.append("\nDiagnose gesammelt: \(folder.path)\n")
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch {
                self.errorMessage = "Die Diagnose konnte nicht gesammelt werden: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Rosetta and Wine setup

    func installRosetta() {
        guard !rosettaInstalling else { return }
        rosettaInstalling = true
        let log = self.log
        Task {
            do {
                let ok = try await Rosetta.install(log: log)
                self.rosettaInstalled = ok
                if !ok {
                    self.errorMessage = "Rosetta 2 konnte nicht automatisch installiert werden. "
                        + "Bitte im Terminal ausführen:\n\(Rosetta.manualCommand)"
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.rosettaInstalling = false
        }
    }

    /// Downloads whatever is missing: Wine first, then its support package.
    func installWine() {
        guard let config, !wineInstallRunning else { return }
        wineInstallRunning = true
        installPhase = .downloading(0)

        let paths = self.paths
        let log = self.log
        let onPhase: @Sendable (WineInstallPhase) -> Void = { phase in
            Task { @MainActor in
                // Ignore progress that arrives after the install ended.
                guard self.wineInstallRunning else { return }
                self.installPhase = phase
            }
        }
        Task {
            do {
                if self.wineInstallation == nil {
                    self.installLabel = "Wine"
                    let installer = WineInstaller(paths: paths, config: config.wine, log: log)
                    self.wineInstallation = try await installer.install(onPhase: onPhase)
                }
                if let support = config.support, self.supportInstallation == nil {
                    self.installLabel = "Laufzeitbibliotheken und Grafikschichten"
                    self.installPhase = .downloading(0)
                    let installer = SupportInstaller(paths: paths, config: support, log: log)
                    self.supportInstallation = try await installer.install(onPhase: onPhase)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.wineInstallRunning = false
            self.installPhase = nil
            self.installLabel = nil
        }
    }

    // MARK: Bottles

    func refreshBottles() {
        do {
            bottles = try store.list()
        } catch {
            errorMessage = error.localizedDescription
        }
        if let selectedBottleID, !bottles.contains(where: { $0.id == selectedBottleID }) {
            self.selectedBottleID = nil
        }
        if selectedBottleID == nil {
            selectedBottleID = bottles.first?.id
        }
    }

    func prefixURL(for bottle: Bottle) -> URL {
        store.prefixURL(for: bottle.id)
    }

    func createBottle(named name: String) {
        guard let runner, busyMessage == nil else { return }
        let bottle: Bottle
        do {
            bottle = try store.create(name: name)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        refreshBottles()
        selectedBottleID = bottle.id

        let prefix = store.prefixURL(for: bottle.id)
        busyMessage = "Bottle \"\(bottle.name)\" wird eingerichtet. Das dauert beim ersten Mal ein bis zwei Minuten."
        Task {
            do {
                try await runner.initializePrefix(prefix: prefix, settings: bottle.settings)
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.busyMessage = nil
        }
    }

    func renameBottle(_ bottle: Bottle, to name: String) {
        do {
            try store.rename(bottle.id, to: name)
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshBottles()
    }

    /// Ends the bottle's Wine processes, then deletes it for good.
    func deleteBottle(_ bottle: Bottle) {
        let runner = self.runner
        let prefix = store.prefixURL(for: bottle.id)
        busyMessage = "Bottle \"\(bottle.name)\" wird gelöscht."
        Task {
            if let runner {
                _ = try? await runner.killAll(prefix: prefix, settings: bottle.settings)
            }
            do {
                try self.store.delete(bottle.id)
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.busyMessage = nil
            self.refreshBottles()
        }
    }

    /// Saves changed settings and writes those that live in the registry.
    func updateSettings(of bottle: Bottle, _ change: (inout BottleSettings) -> Void) {
        // Start from what is stored now, not from the caller's copy, so two
        // changes in a row cannot overwrite each other.
        let bottle = bottles.first { $0.id == bottle.id } ?? bottle
        var updated = bottle
        change(&updated.settings)
        guard updated.settings != bottle.settings else { return }
        do {
            try store.update(updated)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        refreshBottles()

        let registryChanged = updated.settings.windowsVersion != bottle.settings.windowsVersion
            || updated.settings.retinaMode != bottle.settings.retinaMode
        guard registryChanged, let runner else { return }
        let prefix = store.prefixURL(for: bottle.id)
        Task {
            do {
                try await runner.applySettings(prefix: prefix, settings: updated.settings)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Steam

    static let steamBottleName = "Steam"

    func isSteamInstalled(in bottle: Bottle) -> Bool {
        guard let config else { return false }
        return SteamLocation.isInstalled(prefix: store.prefixURL(for: bottle.id), config: config.steam)
    }

    var steamArgumentPresets: [RuntimeConfig.Steam.ArgumentPreset] {
        config?.steam.argumentPresets ?? []
    }

    /// The start parameters Steam gets in this bottle, as one line of text.
    func steamArgumentsText(for bottle: Bottle) -> String {
        guard let config else { return "" }
        return CommandLineArguments.join(SteamLauncher.arguments(for: bottle.settings, config: config.steam))
    }

    func usesDefaultSteamArguments(_ bottle: Bottle) -> Bool {
        bottle.settings.steamArguments == nil
    }

    /// Saves start parameters for this bottle. `nil` goes back to the
    /// defaults from runtimes.json.
    func setSteamArguments(_ arguments: [String]?, for bottle: Bottle) {
        updateSettings(of: bottle) { $0.steamArguments = arguments }
    }

    /// The Chromium switches the helper library adds to Steam's browser
    /// process in this bottle, as one line of text.
    func steamBrowserArgumentsText(for bottle: Bottle) -> String {
        guard let config else { return "" }
        return CommandLineArguments.join(bottle.settings.steamBrowserArguments ?? config.steam.uiFix.browserArguments)
    }

    /// `nil` goes back to the defaults from runtimes.json.
    func setSteamBrowserArguments(_ arguments: [String]?, for bottle: Bottle) {
        updateSettings(of: bottle) { $0.steamBrowserArguments = arguments }
    }

    var steamUIFixEnabled: Bool {
        config?.steam.uiFix.enabled ?? false
    }

    /// One click: make a "Steam" bottle if there is none, install Steam in
    /// it and start it.
    func setUpSteam() {
        guard let config, let runner, busyMessage == nil else { return }
        busyMessage = "Steam wird vorbereitet …"
        Task {
            do {
                let bottle: Bottle
                if let existing = self.bottles.first(where: {
                    $0.name.compare(AppModel.steamBottleName, options: [.caseInsensitive]) == .orderedSame
                }) {
                    bottle = existing
                    self.selectedBottleID = bottle.id
                } else {
                    bottle = try self.store.create(name: AppModel.steamBottleName)
                    self.refreshBottles()
                    self.selectedBottleID = bottle.id
                    self.busyMessage = "Windows-Umgebung für Steam wird eingerichtet. Das dauert ein bis zwei Minuten."
                    try await runner.initializePrefix(
                        prefix: self.store.prefixURL(for: bottle.id),
                        settings: bottle.settings
                    )
                }

                if !self.isSteamInstalled(in: bottle) {
                    try await self.performSteamInstall(in: bottle, config: config, runner: runner)
                }
                self.busyMessage = nil
                self.launchSteam(in: bottle)
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.busyMessage = nil
        }
    }

    /// Installs Steam into an existing bottle.
    func installSteam(in bottle: Bottle) {
        guard let config, let runner, busyMessage == nil else { return }
        busyMessage = "Steam wird vorbereitet …"
        Task {
            do {
                try await self.performSteamInstall(in: bottle, config: config, runner: runner)
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.busyMessage = nil
        }
    }

    private func performSteamInstall(in bottle: Bottle, config: RuntimeConfig, runner: WineRunner) async throws {
        let installer = SteamInstaller(paths: paths, config: config.steam, runner: runner, log: log)
        try await installer.install(
            prefix: store.prefixURL(for: bottle.id),
            settings: bottle.settings
        ) { phase in
            Task { @MainActor in
                // Only while the install is still the running operation.
                guard self.busyMessage != nil else { return }
                switch phase {
                case .downloading:
                    self.busyMessage = "Der Steam-Installer wird geladen …"
                case .installing:
                    self.busyMessage = "Steam wird installiert …"
                }
            }
        }
    }

    // MARK: Game library

    /// Installed games per bottle, as last read from Steam's files.
    @Published private(set) var steamGames: [Bottle.ID: [SteamApp]] = [:]
    /// Anti-cheat warnings per bottle, by Steam app id.
    @Published private(set) var antiCheatHints: [Bottle.ID: [Int: AntiCheatHint]] = [:]

    /// Reads which games Steam has installed in the bottle and which of
    /// them use an anti-cheat that does not run under Wine.
    func refreshLibrary(for bottle: Bottle) {
        guard let config else { return }
        let prefix = store.prefixURL(for: bottle.id)
        let steamDirectory = SteamLocation.directory(prefix: prefix, config: config.steam)
        let hidden = config.steam.hiddenAppIDs
        let antiCheat = config.antiCheat
        Task {
            let (games, hints) = await Task.detached { () -> ([SteamApp], [Int: AntiCheatHint]) in
                let games = SteamLibrary.games(
                    SteamLibrary.scan(steamDirectory: steamDirectory, prefix: prefix), hiding: hidden)
                var hints: [Int: AntiCheatHint] = [:]
                if let antiCheat {
                    for game in games {
                        hints[game.appID] = AntiCheatCheck.hint(for: game, config: antiCheat)
                    }
                }
                return (games, hints)
            }.value
            self.steamGames[bottle.id] = games
            self.antiCheatHints[bottle.id] = hints
        }
    }

    /// A cached cover picture for a game, if Steam has one.
    func coverImage(for game: SteamApp, in bottle: Bottle) -> URL? {
        guard let config else { return nil }
        let steamDirectory = SteamLocation.directory(prefix: store.prefixURL(for: bottle.id), config: config.steam)
        return SteamLibrary.coverImage(appID: game.appID, steamDirectory: steamDirectory)
    }

    /// Starts a game through Steam (starting Steam first if needed).
    func play(_ game: SteamApp, in bottle: Bottle) {
        log.append("\nStarte \(game.name) (\(game.appID)) über Steam.\n")
        if let hint = antiCheatHints[bottle.id]?[game.appID] {
            log.append("Hinweis: \(hint.systems.joined(separator: ", ")) (\(hint.evidence.joined(separator: "; "))).\n")
        }
        launchSteam(in: bottle, extraArguments: [SteamLibrary.runGameArgument(appID: game.appID)])
    }

    func launchSteam(in bottle: Bottle, extraArguments: [String] = []) {
        guard let config, let wineInstallation, busyMessage == nil else { return }
        // Read the bottle again: its start parameters may just have changed.
        let current = bottles.first { $0.id == bottle.id } ?? bottle
        let prefix = store.prefixURL(for: current.id)
        let arguments = SteamLauncher.arguments(for: current.settings, config: config.steam) + extraArguments
        let uiFix = config.steam.uiFix
        let browserArguments = current.settings.steamBrowserArguments ?? uiFix.browserArguments
        let log = self.log

        let paths = self.paths
        let backend = current.settings.graphicsBackend
        let layer = config.graphicsLayer(for: backend)

        if let reason = config.pauseReason(for: backend) {
            errorMessage = "\(reason)\n\nBitte bei der Bottle unter „Grafik“ eine andere Auswahl treffen, zum Beispiel DXMT."
            return
        }

        Task {
            do {
                // Without its copy of Wine (removed, or a new revision of
                // the layer) the bottle would quietly run on plain Wine.
                if let layer, self.wineVariants[backend] == nil {
                    // Licensed layers are fetched only with the user's consent.
                    if layer.license != nil,
                       !WineVariantInstaller.hasLayerFiles(paths: paths, layer: layer) {
                        throw LayerNotSetUp(layer: layer.name)
                    }
                    try await self.installVariant(for: backend, base: wineInstallation, config: config)
                }
                guard let runner = self.runner else { return }
                let launcher = SteamLauncher(config: config.steam, runner: runner)
                if let layer {
                    let added = try WineVariantInstaller.installPrefixLibraries(layer: layer, paths: paths, prefix: prefix)
                    if !added.isEmpty {
                        log.append("\n\(layer.name): in die Bottle gelegt: \(added.joined(separator: ", "))\n")
                    }
                }
                var environment: [String: String] = [:]
                if uiFix.enabled {
                    guard let resources = AppModel.resourceDirectory(containing: uiFix.library) else {
                        throw SteamUIFixError.missingFile(uiFix.library)
                    }
                    let fix = SteamUIFix(config: uiFix, resourcesDirectory: resources, wine: wineInstallation)
                    try await fix.install(prefix: prefix, settings: current.settings, runner: runner)
                    environment = SteamUIFix.environment(browserArguments: browserArguments)
                    log.append("\nSteam-Fensterkorrektur aktiv, Browser-Parameter: \(CommandLineArguments.join(browserArguments))\n")
                }
                log.append("\nStarte Steam mit: \(CommandLineArguments.join(arguments))\n")
                try await launcher.launch(
                    prefix: prefix, settings: current.settings,
                    extraArguments: extraArguments, environment: environment)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Quits Steam and ends every Wine process of the bottle.
    func quitSteam(in bottle: Bottle) {
        guard let config, let runner, busyMessage == nil else { return }
        let launcher = SteamLauncher(config: config.steam, runner: runner)
        let prefix = store.prefixURL(for: bottle.id)
        busyMessage = "Steam wird beendet …"
        Task {
            await launcher.shutdown(prefix: prefix, settings: bottle.settings)
            self.busyMessage = nil
        }
    }

    // MARK: Running things

    /// Starts a Wine tool such as `winecfg` or `regedit` in the bottle.
    func runWineTool(_ tool: String, in bottle: Bottle) {
        guard let runner else { return }
        let prefix = store.prefixURL(for: bottle.id)
        Task {
            do {
                try await runner.run([tool], prefix: prefix, settings: bottle.settings)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Starts a `.exe` or `.msi` from anywhere on the Mac in the bottle.
    func runFile(_ file: URL, in bottle: Bottle) {
        guard let runner else { return }
        let prefix = store.prefixURL(for: bottle.id)
        Task {
            do {
                try await runner.runFile(file, prefix: prefix, settings: bottle.settings)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func stopWine(in bottle: Bottle) {
        guard let runner else { return }
        let prefix = store.prefixURL(for: bottle.id)
        Task {
            _ = try? await runner.killAll(prefix: prefix, settings: bottle.settings)
        }
    }

    func revealInFinder(_ bottle: Bottle) {
        let driveC = store.prefixURL(for: bottle.id).appendingPathComponent("drive_c", isDirectory: true)
        let target = FileManager.default.fileExists(atPath: driveC.path) ? driveC : store.directory(for: bottle.id)
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }
}

/// A bottle uses a licensed layer whose files were never fetched.
struct LayerNotSetUp: LocalizedError {
    let layer: String
    var errorDescription: String? {
        "\(layer) ist noch nicht eingerichtet. Bitte bei der Bottle unter „Grafik“ \(layer) auswählen und der Lizenz zustimmen."
    }
}
