import FilmulationCore
import PhotosUI
import SwiftUI

struct EditorView: View {
    @Environment(EditorStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                if store.photos.isEmpty {
                    EmptyState()
                } else {
                    VStack(spacing: 0) {
                        if store.photos.count > 1 { PhotoStrip() }
                        Preview()
                        Controls()
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Filmulation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PhotosPicker(selection: $store.pickerItems, maxSelectionCount: 30, matching: .images,
                                 photoLibrary: .shared()) {
                        Image(systemName: "photo.badge.plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { SaveButton() }
            }
            .overlay(alignment: .bottom) { Toast() }
        }
    }
}

private struct EmptyState: View {
    @Environment(EditorStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 16) {
            Image(systemName: "camera.filters")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Film looks for any photo")
                .font(.title3.weight(.semibold))
            PhotosPicker(selection: $store.pickerItems, maxSelectionCount: 30, matching: .images,
                         photoLibrary: .shared()) {
                Label("Choose Photos", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(.white, in: Capsule())
                    .foregroundStyle(.black)
            }
            if store.isLoading { ProgressView().padding(.top, 8) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PhotoStrip: View {
    @Environment(EditorStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.photos) { p in
                    Button { store.select(p.id) } label: {
                        ZStack {
                            Color.gray.opacity(0.2)
                            if let t = p.thumbnail {
                                Image(decorative: t, scale: 1).resizable().aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.white, lineWidth: store.selectedID == p.id ? 2 : 0))
                    }
                    .contextMenu {
                        Button("Remove", systemImage: "trash", role: .destructive) { store.remove(p.id) }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 58)
    }
}

private struct Preview: View {
    @Environment(EditorStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                if let img = store.showBefore ? store.original : (store.rendered ?? store.original) {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(alignment: .topLeading) {
                if store.original != nil {
                    Text(previewLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(10)
                }
            }

            Picker("", selection: $store.showBefore) {
                Text("Before").tag(true)
                Text("After").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding(.top, 6)
    }

    private var previewLabel: String {
        let name = store.settings.look?.name ?? "Original"
        if store.showBefore { return "Before" }
        if let error = store.renderError, store.rendered == nil { return "Couldn't apply \(name): \(error)" }
        return "After · \(name)"
    }
}

private struct Controls: View {
    @Environment(EditorStore.self) private var store
    @State private var showRecipes = false

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Menu {
                    Picker("Camera", selection: Binding(get: { store.settings.camera?.id ?? "" },
                                                        set: { store.chooseCamera(Cameras.camera($0)) })) {
                        Text("Any camera (all looks)").tag("")
                        ForEach(["X Series", "GFX Series"], id: \.self) { series in
                            Section(series) {
                                ForEach(Cameras.all.filter { $0.series == series }) { Text($0.name).tag($0.id) }
                            }
                        }
                    }
                } label: {
                    Label(store.settings.camera?.name ?? "Any camera", systemImage: "camera")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(white: 0.18), in: Capsule())
                }
                Button { showRecipes = true } label: {
                    Label(store.recipe?.name ?? "Recipes", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(store.recipe == nil ? Color(white: 0.18) : Color.accentColor.opacity(0.35),
                                    in: Capsule())
                }
                .disabled(store.availableRecipes.isEmpty)
                if store.recipe != nil {
                    Button { store.clearRecipe() } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .sheet(isPresented: $showRecipes) {
                RecipeSheet(recipes: store.availableRecipes, swatches: store.swatches) { r in
                    store.applyRecipe(r)
                    showRecipes = false
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        LookCard(name: "Original", swatch: store.original, selected: store.settings.look == nil) {
                            store.chooseLook(nil)
                            withAnimation { proxy.scrollTo("original", anchor: .center) }
                        }
                        .id("original")
                        ForEach(store.availableLooks) { look in
                            LookCard(name: look.name, swatch: store.swatches[look.id],
                                     selected: store.settings.look == look) {
                                store.chooseLook(look)
                                withAnimation { proxy.scrollTo(look.id, anchor: .center) }
                            }
                            .id(look.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if let r = store.recipe {
                Text("\(r.name) by \(r.creator) · \(r.summary)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .padding(.horizontal, 16)
            } else {
                Text(store.settings.look?.blurb ?? (store.availableLooks.isEmpty
                    ? "No film looks are installed yet. Grain, strength and saving still work."
                    : "Your photo's own colours, with no film look."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 10) {
                HStack {
                    Text("Strength").font(.subheadline).frame(width: 70, alignment: .leading)
                    Slider(value: Binding(get: { Double(store.settings.strength) },
                                          set: { store.settings.strength = Float($0) }), in: 0...1)
                    Text("\(Int(store.settings.strength * 100))%")
                        .font(.subheadline.monospacedDigit()).frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("Grain").font(.subheadline).frame(width: 70, alignment: .leading)
                    Picker("Grain", selection: $store.settings.grain) {
                        ForEach(GrainAmount.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    Text("Size").font(.subheadline).frame(width: 70, alignment: .leading)
                    Picker("Size", selection: $store.settings.grainSize) {
                        ForEach(GrainSize.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(store.settings.grain == .off)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(Color(white: 0.08))
    }
}

private struct LookCard: View {
    let name: String
    let swatch: CGImage?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Color.gray.opacity(0.2)
                    if let swatch {
                        Image(decorative: swatch, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: selected ? 2.5 : 0))
                Text(name)
                    .font(.caption2.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? .white : .secondary)
                    .lineLimit(1)
                    .frame(width: 80)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SaveButton: View {
    @Environment(EditorStore.self) private var store

    var body: some View {
        if let p = store.saveProgress {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("\(p.done)/\(p.total)").font(.caption.monospacedDigit())
            }
        } else if store.photos.count > 1 {
            Menu {
                Button("Save This Photo", systemImage: "square.and.arrow.down") { store.save(all: false) }
                Button("Save All \(store.photos.count) Photos", systemImage: "square.and.arrow.down.on.square") {
                    store.save(all: true)
                }
            } label: { Text("Save").bold() }
        } else {
            Button { store.save(all: false) } label: { Text("Save").bold() }
                .disabled(store.selected == nil)
        }
    }
}

private struct Toast: View {
    @Environment(EditorStore.self) private var store

    var body: some View {
        if let text = store.toast {
            HStack(spacing: 12) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                if store.toastOpensPhotos {
                    Button("Open Photos") {
                        if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
                    }
                    .font(.subheadline.weight(.bold))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 30)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: text) {
                try? await Task.sleep(for: .seconds(store.toastOpensPhotos ? 4 : 2.5))
                withAnimation { store.toast = nil }
            }
        }
    }
}

private struct RecipeSheet: View {
    let recipes: [Recipe]
    let swatches: [String: CGImage]
    let choose: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Recipe] {
        guard !query.isEmpty else { return recipes }
        return recipes.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.creator.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { r in
                Button { choose(r) } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Color.gray.opacity(0.2)
                            if let id = r.lookID, let s = swatches[id] {
                                Image(decorative: s, scale: 1).resizable().aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.body.weight(.semibold))
                            Text("by \(r.creator)").font(.caption).foregroundStyle(.secondary)
                            Text(r.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .searchable(text: $query, prompt: "Name, film or creator")
            .navigationTitle("\(recipes.count) Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Text("Community recipes from open-fuji-recipes. Tone, colour and Color Chrome are approximated.")
                    .font(.caption2).foregroundStyle(.secondary).padding(8)
            }
        }
    }
}
