import AppKit
import CueCore
import SwiftUI

@main
struct NotchCueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NotchCue", systemImage: "text.viewfinder") {
            MenuContent(model: AppModel.shared)
        }
        Settings {
            SettingsView(model: AppModel.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.launch() }
    }
}

private struct MenuContent: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(model.isActive ? "Pause Prompting" : "Start Prompting") { model.toggle() }
            .keyboardShortcut("p", modifiers: [.control, .option, .command])
        Button("Restart from Beginning") { model.restart() }
            .keyboardShortcut("r", modifiers: [.control, .option, .command])
        Button(model.panelShown ? "Hide Prompter" : "Show Prompter") { model.toggleVisibility() }
            .keyboardShortcut("h", modifiers: [.control, .option, .command])
        Divider()
        Button("Edit Script…") { open(.script) }
        Button("Settings…") { open(model.settingsPage) }
            .keyboardShortcut(",")
        Divider()
        Button("Quit NotchCue") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open(_ page: SettingsPage) {
        model.settingsPage = page
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openSettings()
    }
}
