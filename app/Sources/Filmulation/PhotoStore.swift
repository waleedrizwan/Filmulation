import AppKit
import FilmulationCore
import Observation
import UniformTypeIdentifiers

struct Photo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var thumbnail: CGImage?

    static func == (a: Photo, b: Photo) -> Bool { a.id == b.id && (a.thumbnail == nil) == (b.thumbnail == nil) }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// App state and the render pipeline. Heavy work runs off the main actor; a generation counter
/// drops results that arrive after the user has already moved on.
@MainActor @Observable
final class PhotoStore {
    nonisolated static let previewSize = 2000
    nonisolated static let swatchSize = 220

    var photos: [Photo] = []
    var selectedID: Photo.ID?
    var settings = RenderSettings() {
        didSet { settingsChanged(from: oldValue) }
    }
    /// The recipe currently applied (its look, grain and adjustments are in `settings`).
    private(set) var recipe: Recipe?

    private(set) var original: CGImage?
    private(set) var rendered: CGImage?
    private(set) var swatches: [String: CGImage] = [:]
    private(set) var isRendering = false
    /// Why the current settings couldn't be rendered (shown over the original instead of the look).
    private(set) var renderError: String?
    private(set) var exportProgress: (done: Int, total: Int)?
    var message: String?
    /// true while the user is looking at the untouched original; any settings change flips back to the look.
    var showBefore = false

    @ObservationIgnored private var base: GPUImage?
    /// Bumped on every render request; stale preview renders are dropped.
    @ObservationIgnored private var generation = 0
    /// Bumped only when the selected photo changes; stale swatch renders are dropped.
    @ObservationIgnored private var photoToken = 0

    var selected: Photo? { photos.first { $0.id == selectedID } }

    // MARK: adding photos

    func add(_ urls: [URL]) {
        let known = Set(photos.map(\.url))
        let new = expand(urls).filter { !known.contains($0) }
        guard !new.isEmpty else {
            if !urls.isEmpty, photos.isEmpty { message = "No supported photos found (JPEG, PNG, HEIC, TIFF, WebP)." }
            return
        }
        photos += new.map { Photo(url: $0) }
        if selectedID == nil { select(photos[photos.count - new.count].id) }
        for url in new {
            Task.detached(priority: .utility) {
                let thumb = try? PhotoIO.decode(.url(url), maxPixelSize: 160)
                await MainActor.run {
                    if let i = self.photos.firstIndex(where: { $0.url == url }) { self.photos[i].thumbnail = thumb }
                }
            }
        }
    }

    private func expand(_ urls: [URL]) -> [URL] {
        let types = PhotoIO.supportedTypes
        var out: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                         options: [.skipsHiddenFiles])) ?? []
                out += expand(items.sorted { $0.lastPathComponent < $1.lastPathComponent })
            } else if let t = UTType(filenameExtension: url.pathExtension), types.contains(where: { t.conforms(to: $0) }) {
                out.append(url)
            }
        }
        return out
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = PhotoIO.supportedTypes
        panel.message = "Choose photos or a folder of photos"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func remove(_ photo: Photo) {
        photos.removeAll { $0.id == photo.id }
        if selectedID == photo.id { select(photos.first?.id) }
    }

    // MARK: rendering

    func select(_ id: Photo.ID?) {
        selectedID = id
        generation += 1
        photoToken += 1
        base = nil
        original = nil; rendered = nil; swatches = [:]
        renderError = nil
        showBefore = false
        guard let url = selected?.url else { return }
        let token = photoToken
        isRendering = true
        Task.detached(priority: .userInitiated) {
            do {
                let pixels = try PhotoIO.loadRGBA8(.url(url), maxPixelSize: Self.previewSize)
                let gpu = try Self.engine()
                let img = try gpu.upload(pixels)
                let cg = PhotoIO.cgImage(from: pixels)
                await MainActor.run {
                    guard token == self.photoToken else { return }
                    self.base = img
                    self.original = cg
                    self.rerender()
                    self.makeSwatches(url: url, token: token)
                }
            } catch {
                await MainActor.run {
                    self.isRendering = false
                    self.message = "\(error)"
                }
            }
        }
    }

    nonisolated private static func engine() throws -> GPUEngine {
        guard let gpu = GPUEngine.shared else { throw CocoaError(.featureUnsupported) }
        return gpu
    }

    // MARK: camera, look and recipe choices

    var availableLooks: [Look] { Looks.available(for: settings.camera) }
    var availableRecipes: [Recipe] { Recipes.available(for: settings.camera) }

    /// Picking a look (nil = original) by hand leaves any recipe (its tone/colour adjustments are dropped, grain is kept).
    func chooseLook(_ look: Look?) {
        if recipe != nil { recipe = nil; settings.adjustments = Adjustments() }
        settings.look = look
    }

    func chooseCamera(_ camera: Camera?) {
        var s = settings
        s.camera = camera
        if let look = s.look, !Looks.available(for: camera).contains(look) { s.look = Looks.available(for: camera).first }
        if let r = recipe, !Recipes.available(for: camera).contains(r) { recipe = nil; s.adjustments = Adjustments() }
        settings = s
        if let url = selected?.url { makeSwatches(url: url, token: photoToken) }
    }

    func applyRecipe(_ r: Recipe) {
        recipe = r
        settings = r.apply(to: settings)
    }

    func clearRecipe() {
        recipe = nil
        settings.adjustments = Adjustments()
    }

    private func makeSwatches(url: URL, token: Int) {
        let camera = settings.camera
        Task.detached(priority: .utility) {
            guard let small = try? PhotoIO.loadRGBA8(.url(url), maxPixelSize: Self.swatchSize),
                  let gpu = GPUEngine.shared, let img = try? gpu.upload(small) else { return }
            for look in Looks.available(for: camera) {
                guard let cg = try? gpu.renderCGImage(img, settings: RenderSettings(look: look, camera: camera))
                else { continue }
                await MainActor.run {
                    if token == self.photoToken { self.swatches[look.id] = cg }
                }
            }
        }
    }

    private func settingsChanged(from old: RenderSettings) {
        guard old != settings else { return }
        showBefore = false
        rerender()
    }

    /// One GPU pass (look + strength + grain) on the preview-sized photo: a few milliseconds.
    private func rerender() {
        guard let base else { return }
        generation += 1
        let gen = generation, settings = settings
        isRendering = true
        Task.detached(priority: .userInitiated) {
            let result = Result { try Self.engine().renderCGImage(base, settings: settings) }
            await MainActor.run {
                guard gen == self.generation else { return }
                switch result {
                case .success(let cg): self.rendered = cg; self.renderError = nil
                case .failure(let error): self.rendered = nil; self.renderError = "\(error)"
                }
                self.isRendering = false
            }
        }
    }

    // MARK: export

    func export(all: Bool) {
        let sources = all ? photos.map(\.url) : (selected.map { [$0.url] } ?? [])
        guard !sources.isEmpty, exportProgress == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Export \(sources.count) photo\(sources.count == 1 ? "" : "s") at full resolution with "
            + "\(settings.look?.name ?? "the original colours")\(settings.grain == .off ? "" : ", \(settings.grain.rawValue.lowercased()) grain")"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let settings = settings
        exportProgress = (0, sources.count)
        Task.detached(priority: .userInitiated) {
            var written: [URL] = []
            var failures: [String] = []
            for src in sources {
                do { written.append(try Renderer.export(src, settings: settings, to: folder)) }
                catch { failures.append("\(src.lastPathComponent): \(error)") }
                await MainActor.run { self.exportProgress?.done += 1 }
            }
            let (done, failed) = (written, failures)
            await MainActor.run {
                self.exportProgress = nil
                self.message = failed.isEmpty
                    ? "Exported \(done.count) photo\(done.count == 1 ? "" : "s")."
                    : "Exported \(done.count), failed \(failed.count):\n" + failed.joined(separator: "\n")
                if !done.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(done) }
            }
        }
    }
}
