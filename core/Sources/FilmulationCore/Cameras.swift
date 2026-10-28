import Foundation

/// A Fujifilm camera profile: which film simulations it has, which of Fujifilm's per-camera LUT packs
/// supplies its own Eterna / Bleach Bypass, and which recipe sensor generation suits it.
public struct Camera: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let series: String          // "X Series" / "GFX Series"
    public let sensor: String          // shown in the UI
    public let recipeSensor: Int       // open-fuji-recipes "sensor" value (3 = X-Trans III, 4 = X-Trans IV)
    public let lutPack: String?        // key in camera_luts.json (nil = the main GFX ETERNA 55 pack)
    public let looks: Set<String>
}

public enum Cameras {
    private static let mono: Set<String> = ["monochrome", "monochrome-ye", "monochrome-r", "monochrome-g", "sepia"]
    private static let acros: Set<String> = ["acros", "acros-ye", "acros-r", "acros-g"]
    private static let base: Set<String> = ["provia", "velvia", "astia", "classic-chrome", "pro-neg-hi", "pro-neg-std"]
        .reduce(into: mono) { $0.insert($1) }
    // Film simulation line-ups by generation (Fujifilm specs; Reala Ace and Nostalgic Neg are the newest)
    private static let xt2 = base.union(acros)
    private static let gen3 = xt2.union(["eterna"])                                   // X-H1, X-T3, X-T30
    private static let gen4a = gen3.union(["classic-neg"])                            // X-Pro3, X100V
    private static let gen4 = gen4a.union(["eterna-bb"])                              // X-T4, X-S10, X-E4, X-T30 II
    private static let gen5 = gen4.union(["nostalgic-neg"])                           // X-H2S, X-H2, X-T5, X-S20
    private static let all20 = gen5.union(["reala-ace"])                              // newest bodies

    public static let all: [Camera] = [
        Camera(id: "gfx-eterna-55", name: "GFX ETERNA 55", series: "GFX Series", sensor: "GFX 44×33",
               recipeSensor: 4, lutPack: nil, looks: all20),
        Camera(id: "gfx100rf", name: "GFX100RF", series: "GFX Series", sensor: "GFX 102MP", recipeSensor: 4,
               lutPack: "gfx100rf", looks: all20),
        Camera(id: "gfx100sii", name: "GFX100S II", series: "GFX Series", sensor: "GFX 102MP", recipeSensor: 4,
               lutPack: "gfx100sii", looks: all20),
        Camera(id: "gfx100II", name: "GFX100 II", series: "GFX Series", sensor: "GFX 102MP", recipeSensor: 4,
               lutPack: "gfx100II", looks: all20),
        Camera(id: "gfx100s", name: "GFX100S", series: "GFX Series", sensor: "GFX 102MP", recipeSensor: 4,
               lutPack: "gfx100s", looks: gen5),
        Camera(id: "gfx100", name: "GFX100", series: "GFX Series", sensor: "GFX 102MP", recipeSensor: 4,
               lutPack: "gfx100", looks: gen4),
        Camera(id: "x100vi", name: "X100VI", series: "X Series", sensor: "X-Trans 5 HR", recipeSensor: 4,
               lutPack: "x100vi", looks: all20),
        Camera(id: "x-e5", name: "X-E5", series: "X Series", sensor: "X-Trans 5 HR", recipeSensor: 4,
               lutPack: "x-e5", looks: all20),
        Camera(id: "x-t50", name: "X-T50", series: "X Series", sensor: "X-Trans 5 HR", recipeSensor: 4,
               lutPack: "x-t50", looks: all20),
        Camera(id: "x-m5", name: "X-M5", series: "X Series", sensor: "X-Trans 4", recipeSensor: 4,
               lutPack: "x-m5", looks: all20),
        Camera(id: "x-t30iii", name: "X-T30 III", series: "X Series", sensor: "X-Trans 4", recipeSensor: 4,
               lutPack: "x-t30iii", looks: all20),
        Camera(id: "x-h2s", name: "X-H2S", series: "X Series", sensor: "X-Trans 5 HS", recipeSensor: 4,
               lutPack: "x-h2s", looks: gen5),
        Camera(id: "x-h2", name: "X-H2", series: "X Series", sensor: "X-Trans 5 HR", recipeSensor: 4,
               lutPack: "x-h2", looks: gen5),
        Camera(id: "x-t5", name: "X-T5", series: "X Series", sensor: "X-Trans 5 HR", recipeSensor: 4,
               lutPack: "x-t5", looks: gen5),
        Camera(id: "x-s20", name: "X-S20", series: "X Series", sensor: "X-Trans 4", recipeSensor: 4,
               lutPack: "x-s20", looks: gen5),
        Camera(id: "x-t4", name: "X-T4", series: "X Series", sensor: "X-Trans 4", recipeSensor: 4,
               lutPack: "x-t4", looks: gen4),
        Camera(id: "x-s10", name: "X-S10", series: "X Series", sensor: "X-Trans 4", recipeSensor: 4,
               lutPack: "x-s10", looks: gen4),
        Camera(id: "x-e4", name: "X-E4", series: "X Series", sensor: "X-Trans 4", recipeSensor: 4,
               lutPack: "x-e4", looks: gen4),
        Camera(id: "x-t30ii", name: "X-T30 II", series: "X Series", sensor: "X-Trans 4", recipeSensor: 4,
               lutPack: "x-t30ii", looks: gen4),
        Camera(id: "x-pro3", name: "X-Pro3", series: "X Series", sensor: "X-Trans 4", recipeSensor: 4,
               lutPack: "x-pro3", looks: gen4a),
        Camera(id: "x100v", name: "X100V", series: "X Series", sensor: "X-Trans 4", recipeSensor: 4,
               lutPack: "x100v", looks: gen4a),
        Camera(id: "x-t3", name: "X-T3", series: "X Series", sensor: "X-Trans 4", recipeSensor: 4,
               lutPack: "x-t3", looks: gen3),
        Camera(id: "x-t30", name: "X-T30", series: "X Series", sensor: "X-Trans 4", recipeSensor: 4,
               lutPack: "x-t30", looks: gen3),
        Camera(id: "x-h1", name: "X-H1", series: "X Series", sensor: "X-Trans III", recipeSensor: 3,
               lutPack: "x-h1", looks: gen3),
        Camera(id: "x-t2", name: "X-T2", series: "X Series", sensor: "X-Trans III", recipeSensor: 3,
               lutPack: "x-t2", looks: xt2),
    ]

    public static func camera(_ id: String) -> Camera? { all.first { $0.id == id } }

    /// Whether this camera uses its own Fujifilm Eterna / Bleach Bypass LUTs (rather than the shared ones).
    public static func hasOwnEterna(_ camera: Camera) -> Bool {
        guard let pack = camera.lutPack, let m = Looks.cameraLUTs[pack] else { return false }
        return m["eterna"].map { Looks.fileURL($0) != nil } ?? false
    }
}
