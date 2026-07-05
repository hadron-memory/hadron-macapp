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
            // appearance (dark in a light bar, light in a dark bar).
            Image(nsImage: .hadronMenuBar)
        }
        .menuBarExtraStyle(.window)
    }
}
