import SwiftUI
import AppKit

@main
struct UninstallerApp: App {
    init() {
        // Lets the app show a normal window + Dock icon even when run via `swift run` / Xcode ⌘R.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            // A Swift package executable has no app bundle to carry an icon, so set it ourselves.
            if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = icon
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("Uninstaller") {
            ContentView()
                .frame(minWidth: 820, minHeight: 560)
        }
    }
}
