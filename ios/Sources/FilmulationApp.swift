import FilmulationCore
import SwiftUI

@main
struct FilmulationApp: App {
    @State private var store = EditorStore()

    init() {
        // Get the GPU pipeline and all looks ready before the first tap
        DispatchQueue.global(qos: .userInitiated).async { GPUEngine.shared?.preloadLooks() }
    }

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}
