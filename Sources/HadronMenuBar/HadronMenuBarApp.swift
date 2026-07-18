import SwiftUI
import AppKit

@main
struct HadronMenuBarApp: App {
    @StateObject private var state = AppState()

    init() {
        // Menu-bar-only: no Dock icon, no main window in the app switcher.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(state)
        } label: {
            // Monochrome template glyph; macOS tints it for the menu bar
            // appearance (dark in a light bar, light in a dark bar). The
            // accessibility label + help keep the status item discoverable to
            // VoiceOver and on hover now that it carries no visible title.
            Image(nsImage: .hadronMenuBar)
                .accessibilityLabel("Hadron")
                .help("Hadron")
        }
        .menuBarExtraStyle(.window)
    }
}
