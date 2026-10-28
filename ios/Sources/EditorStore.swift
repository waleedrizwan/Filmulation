import FilmulationCore
import Observation
import Photos
import PhotosUI
import SwiftUI

struct EditPhoto: Identifiable {
    let id = UUID()
    let data: Data          // original file bytes (HEIC/JPEG) with all metadata
    var thumbnail: CGImage?
    var source: PhotoSource { .data(data, name: "photo") }
}

/// Editor state. Each photo is decoded once at screen size and kept on the GPU; every settings change
/// is a single Metal pass (a few ms), so sliders and look changes update live.
@MainActor @Observable
final class EditorStore {
    nonisolated static let previewSize = 2048
    nonisolated static let swatchSize = 240

    var photos: [EditPhoto] = []
    var selectedID: EditPhoto.ID?
    var settings = RenderSettings() {
        didSet { if oldValue != settings { showBefore = false; rerender() } }
    }
    var showBefore = false
    /// The recipe currently applied (its look, grain and adjustments are in `settings`).
    private(set) var recipe: Recipe?
    var pickerItems: [PhotosPickerItem] = [] {
        didSet { if !pickerItems.isEmpty { importPicked() } }
    }

    private(set) var original: CGImage?
    private(set) var rendered: CGImage?
    private(set) var swatches: [String: CGImage] = [:]
    private(set) var isLoading = false
    private(set) var saveProgress: (done: Int, total: Int)?
    var toast: String? {
        didSet { if toast == nil { toastOpensPhotos = false } }
    }
    /// When true the toast shows an "Open Photos" button.
    var toastOpensPhotos = false

    @ObservationIgnored private var base: GPUImage?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var photoToken = 0

    var selected: EditPhoto? { photos.first { $0.id == selectedID } }

    // MARK: importing

    private func importPicked() {
        let items = pickerItems
        pickerItems = []
        isLoading = true
        Task {
            var added: [EditPhoto] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                added.append(EditPhoto(data: data))
            }
            isLoading = false
            guard !added.isEmpty else {
                toast = "Couldn't load those photos"
                return
            }
            photos += added
            select(added[0].id)
            for p in added { makeThumbnail(p) }
        }
    }

    private func makeThumbnail(_ p: EditPhoto) {
        Task.detached(priority: .utility) {
            let thumb = try? PhotoIO.decode(p.source, maxPixelSize: 160)
            await MainActor.run {
                if let i = self.photos.firstIndex(where: { $0.id == p.id }) { self.photos[i].thumbnail = thumb }
            }
        }
    }

    func remove(_ id: EditPhoto.ID) {
        photos.removeAll { $0.id == id }
        if selectedID == id { select(photos.first?.id) }
    }

    // MARK: rendering

    func select(_ id: EditPhoto.ID?) {
        selectedID = id
        photoToken += 1
        generation += 1
        base = nil; original = nil; rendered = nil; swatches = [:]
        showBefore = false
        guard let source = selected?.source else { return }
        let token = photoToken
        isLoading = true
        Task.detached(priority: .userInitiated) {
            guard let gpu = GPUEngine.shared,
                  let pixels = try? PhotoIO.loadRGBA8(source, maxPixelSize: Self.previewSize) else {
                await MainActor.run { self.isLoading = false; self.toast = "Couldn't open that photo" }
                return
            }
            let img = gpu.upload(pixels)
            let cg = PhotoIO.cgImage(from: pixels)
            await MainActor.run {
                guard token == self.photoToken else { return }
                self.base = img
                self.original = cg
                self.isLoading = false
                self.rerender()
                self.makeSwatches(source, token: token)
            }
        }
    }

    // MARK: camera, look and recipe choices

    var availableLooks: [Look] { Looks.available(for: settings.camera) }
    var availableRecipes: [Recipe] { Recipes.available(for: settings.camera) }

    /// Picking a look by hand leaves any recipe (its tone/colour adjustments are dropped, grain is kept).
    func chooseLook(_ look: Look) {
        if recipe != nil { recipe = nil; settings.adjustments = Adjustments() }
        settings.look = look
    }

    func chooseCamera(_ camera: Camera?) {
        var s = settings
        s.camera = camera
        if let look = s.look, !Looks.available(for: camera).contains(look) { s.look = Looks.look("provia") }
        if let r = recipe, !Recipes.available(for: camera).contains(r) { recipe = nil; s.adjustments = Adjustments() }
        settings = s
        if let source = selected?.source { makeSwatches(source, token: photoToken) }
    }

    func applyRecipe(_ r: Recipe) {
        recipe = r
        settings = r.apply(to: settings)
    }

    func clearRecipe() {
        recipe = nil
        settings.adjustments = Adjustments()
    }

    private func makeSwatches(_ source: PhotoSource, token: Int) {
        let camera = settings.camera
        Task.detached(priority: .utility) {
            guard let gpu = GPUEngine.shared,
                  let small = try? PhotoIO.loadRGBA8(source, maxPixelSize: Self.swatchSize) else { return }
            let img = gpu.upload(small)
            var all: [String: CGImage] = [:]
            for look in Looks.available(for: camera) {
                all[look.id] = try? gpu.renderCGImage(img, settings: RenderSettings(look: look, camera: camera))
            }
            let done = all
            await MainActor.run { if token == self.photoToken { self.swatches = done } }
        }
    }

    private func rerender() {
        guard let base else { return }
        generation += 1
        let gen = generation, settings = settings
        Task.detached(priority: .userInitiated) {
            let cg = try? GPUEngine.shared?.renderCGImage(base, settings: settings)
            await MainActor.run {
                if gen == self.generation, let cg { self.rendered = cg }
            }
        }
    }

    // MARK: saving

    func save(all: Bool) {
        let targets = all ? photos : (selected.map { [$0] } ?? [])
        guard !targets.isEmpty, saveProgress == nil else { return }
        let settings = settings
        saveProgress = (0, targets.count)
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                saveProgress = nil
                toast = "Allow photo access in Settings to save"
                return
            }
            var saved = 0
            var lastError: String?
            for p in targets {
                let source = p.source
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        try Renderer.jpegData(source, settings: settings)
                    }.value
                    try await PHPhotoLibrary.shared().performChanges {
                        let request = PHAssetCreationRequest.forAsset()
                        // Date it now so it shows up at the bottom of the camera roll, not back at the
                        // original's capture date (the file still keeps the original EXIF and location).
                        request.creationDate = Date()
                        request.addResource(with: .photo, data: data, options: nil)
                    }
                    saved += 1
                } catch {
                    lastError = error.localizedDescription
                }
                saveProgress?.done += 1
            }
            saveProgress = nil
            UINotificationFeedbackGenerator().notificationOccurred(saved == targets.count ? .success : .error)
            if saved == targets.count {
                toast = saved == 1 ? "Saved to your camera roll" : "Saved \(saved) photos to your camera roll"
                toastOpensPhotos = true
            } else {
                toast = "Saved \(saved) of \(targets.count). \(lastError ?? "")"
                toastOpensPhotos = saved > 0
            }
        }
    }
}
