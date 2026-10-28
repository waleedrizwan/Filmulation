import FilmulationCore
import SwiftUI

/// Searchable list of community recipes; picking one applies its look, grain and tone/colour settings.
struct RecipeBrowser: View {
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
        VStack(spacing: 0) {
            HStack {
                Text("Recipes").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            TextField("Search by name, film or creator", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
            List(filtered) { r in
                Button { choose(r) } label: { RecipeRow(recipe: r, swatch: r.lookID.flatMap { swatches[$0] }) }
                    .buttonStyle(.plain)
            }
            Text("Community recipes from open-fuji-recipes. Tone, colour and Color Chrome are approximated; "
                 + "sharpness, noise reduction and clarity aren't applied.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(12)
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe
    let swatch: CGImage?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Color.gray.opacity(0.15)
                if let swatch { Image(decorative: swatch, scale: 1).resizable().aspectRatio(contentMode: .fill) }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(recipe.name).font(.body.weight(.semibold))
                    Text("by \(recipe.creator)").font(.caption).foregroundStyle(.secondary)
                }
                Text(recipe.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
