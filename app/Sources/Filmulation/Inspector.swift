import FilmulationCore
import SwiftUI

struct Inspector: View {
    @Environment(PhotoStore.self) private var store
    @State private var showRecipes = false

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Camera") {
                        Picker("Camera", selection: Binding(get: { store.settings.camera?.id ?? "" },
                                                            set: { store.chooseCamera(Cameras.camera($0)) })) {
                            Text("Any camera (all looks)").tag("")
                            ForEach(["X Series", "GFX Series"], id: \.self) { series in
                                Section(series) {
                                    ForEach(Cameras.all.filter { $0.series == series }) { Text($0.name).tag($0.id) }
                                }
                            }
                        }
                        .labelsHidden()
                        Text(cameraNote)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    section("Recipe") {
                        if let r = store.recipe {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).font(.body.weight(.semibold))
                                    Text("by \(r.creator)").font(.caption).foregroundStyle(.secondary)
                                    Text(r.summary).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Button("Clear") { store.clearRecipe() }.controlSize(.small)
                            }
                        }
                        Button {
                            showRecipes = true
                        } label: {
                            Label("Browse \(store.availableRecipes.count) recipes…", systemImage: "list.bullet.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(store.availableRecipes.isEmpty)
                    }

                    section("Film Simulation") {
                        VStack(spacing: 4) {
                            ForEach(store.availableLooks) { look in
                                LookRow(look: look, swatch: store.swatches[look.id],
                                        selected: store.settings.look == look) {
                                    store.chooseLook(look)
                                }
                            }
                        }
                    }

                    section("Strength") {
                        HStack {
                            Slider(value: Binding(get: { Double(store.settings.strength) },
                                                  set: { store.settings.strength = Float($0) }), in: 0...1)
                            Text("\(Int(store.settings.strength * 100))%")
                                .monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }

                    section("Grain") {
                        Picker("Amount", selection: $store.settings.grain) {
                            ForEach(GrainAmount.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Picker("Size", selection: $store.settings.grainSize) {
                            ForEach(GrainSize.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(store.settings.grain == .off)
                    }
                }
                .padding(16)
            }

            Divider()
            VStack(spacing: 8) {
                if let p = store.exportProgress {
                    ProgressView(value: Double(p.done), total: Double(p.total)) {
                        Text("Exporting \(p.done + 1 > p.total ? p.total : p.done + 1) of \(p.total)…").font(.caption)
                    }
                } else {
                    Button { store.export(all: false) } label: {
                        Label("Export Photo…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.selected == nil)
                    Button { store.export(all: true) } label: {
                        Text("Export All \(store.photos.count) Photos…").frame(maxWidth: .infinity)
                    }
                    .disabled(store.photos.count < 2)
                }
            }
            .padding(16)
        }
        .background(.background)
        .sheet(isPresented: $showRecipes) {
            RecipeBrowser(recipes: store.availableRecipes, swatches: store.swatches) { r in
                store.applyRecipe(r)
                showRecipes = false
            }
            .frame(minWidth: 520, minHeight: 560)
        }
    }

    private var cameraNote: String {
        guard let cam = store.settings.camera else {
            return "Every film simulation. Pick a camera to see only the looks it has."
        }
        let own = Cameras.hasOwnEterna(cam) && cam.looks.contains("eterna")
            ? " Eterna uses this camera's own Fujifilm LUT." : ""
        return "\(store.availableLooks.count) looks on the \(cam.name) (\(cam.sensor)).\(own)"
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// One film simulation: a preview of the current photo in that look, its name and what it does.
private struct LookRow: View {
    let look: Look
    let swatch: CGImage?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Color.gray.opacity(0.15)
                    if let swatch {
                        Image(decorative: swatch, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(look.name)
                        .font(.body.weight(.semibold))
                    Text(look.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
            .padding(6)
            .background(selected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
