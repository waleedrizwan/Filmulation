import FilmulationCore
import SwiftUI

struct ContentView: View {
    @Environment(PhotoStore.self) private var store
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            PhotoList()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            HStack(spacing: 0) {
                Group {
                    if store.photos.isEmpty {
                        DropPrompt()
                    } else {
                        BeforeAfterView(before: store.original, after: store.rendered,
                                        lookName: store.settings.look?.name ?? "Original",
                                        busy: store.isRendering, error: store.renderError,
                                        showBefore: $store.showBefore)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.09))
                Divider()
                Inspector()
                    .frame(width: 340)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.add(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: takePendingURLs)
        .onReceive(NotificationCenter.default.publisher(for: .openPhotos)) { _ in takePendingURLs() }
        .alert("Filmulation", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }

    private func takePendingURLs() {
        let urls = AppDelegate.pendingURLs
        AppDelegate.pendingURLs = []
        if !urls.isEmpty { store.add(urls) }
    }
}

private struct DropPrompt: View {
    @Environment(PhotoStore.self) private var store

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 54, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Drop photos or a folder here")
                .font(.title2)
            Text("JPEG, PNG, HEIC straight from your iPhone")
                .foregroundStyle(.secondary)
            Button("Choose Photos…") { store.showOpenPanel() }
                .controlSize(.large)
                .padding(.top, 6)
        }
        .foregroundStyle(.white)
    }
}

private struct PhotoList: View {
    @Environment(PhotoStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: Binding(get: { store.selectedID }, set: { store.select($0) })) {
            ForEach(store.photos) { photo in
                HStack(spacing: 10) {
                    Group {
                        if let t = photo.thumbnail {
                            Image(decorative: t, scale: 1).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(photo.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .tag(photo.id)
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
                    Button("Remove from List") { store.remove(photo) }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { store.showOpenPanel() } label: { Label("Add Photos", systemImage: "plus") }
            }
        }
    }
}
