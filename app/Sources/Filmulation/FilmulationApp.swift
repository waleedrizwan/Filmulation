import AppKit
import FilmulationCore
import SwiftUI

@main
struct FilmulationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = PhotoStore()

    var body: some Scene {
        WindowGroup("Filmulation") {
            ContentView()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Photos…") { store.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .saveItem) {
                Button("Export Photo…") { store.export(all: false) }
                    .keyboardShortcut("e")
                    .disabled(store.selected == nil)
                Button("Export All…") { store.export(all: true) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.photos.isEmpty)
            }
        }
    }
}

extension Notification.Name {
    static let openPhotos = Notification.Name("FilmulationOpenPhotos")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Files opened before the window existed (e.g. `open -a Filmulation a.jpg`, or dropped on the Dock icon).
    @MainActor static var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { AppDelegate.pendingURLs += urls }
        NotificationCenter.default.post(name: .openPhotos, object: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (swift run) rather than from the .app bundle
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.global(qos: .userInitiated).async { GPUEngine.shared?.preloadLooks() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
