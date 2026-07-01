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
        MenuBarExtra("Hadron", systemImage: "brain") {
            MenuContentView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}
