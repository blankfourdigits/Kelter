import AppKit
import SwiftUI

@main
struct KelterMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @AppStorage("showTestView") private var showTestView = false

    var body: some Scene {
        WindowGroup("Kelter") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Toggle("Testansicht", isOn: $showTestView)
                    .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }

        Settings {
            AppSettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started with `swift run` there is no app bundle, and macOS would
        // treat the process as a background tool without a Dock icon.
        NSApp.setActivationPolicy(.regular)
        // Set the icon explicitly: with `swift run` there is no bundle icon,
        // and a cached blank icon would otherwise stay in the Dock.
        if let icon = Self.appIcon() {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate()
    }

    /// AppIcon.icns from the app bundle, or from Resources/ next to the
    /// package when started with `swift run`.
    private static func appIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        var folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = folder.appendingPathComponent("Resources/AppIcon.icns")
            if FileManager.default.fileExists(atPath: candidate.path) { return NSImage(contentsOf: candidate) }
            folder.deleteLastPathComponent()
        }
        return nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
