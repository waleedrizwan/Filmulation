import SwiftUI

/// Shows the processed photo, or the original while "Before" is switched on.
struct BeforeAfterView: View {
    let before: CGImage?
    let after: CGImage?
    let lookName: String
    let busy: Bool
    /// Set when the look couldn't be applied; the original is shown with this message instead of a spinner.
    let error: String?
    @Binding var showBefore: Bool

    private var label: String {
        if showBefore { return "Before: original" }
        if let error, after == nil { return "Couldn't apply \(lookName): \(error)" }
        return "After: \(lookName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let shown = showBefore ? before : (after ?? (error != nil ? before : nil)) {
                    Image(decorative: shown, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topLeading) {
                            Text(label)
                                .font(.callout.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.black.opacity(0.6), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(10)
                        }
                } else {
                    ProgressView().controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(20)

            HStack(spacing: 12) {
                Picker("", selection: $showBefore) {
                    Text("Before").tag(true)
                    Text("After").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                Text("or press Space")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .background {
            // Space toggles Before / After
            Button("") { showBefore.toggle() }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
        }
    }
}
