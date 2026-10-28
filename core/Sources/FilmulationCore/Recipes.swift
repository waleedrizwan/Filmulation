import Foundation

/// Camera settings beyond the film simulation, applied by the GPU engine around the LUT.
/// Step sizes are estimates (Fujifilm doesn't publish them), tuned by eye.
public struct Adjustments: Equatable, Sendable {
    public var exposure: Float = 0      // stops (recipe "ev")
    public var wbRed: Float = 0         // WB shift, -9...+9
    public var wbBlue: Float = 0
    public var highlight: Float = 0     // Highlight tone, -2...+4 (DR200/400 soften this further)
    public var shadow: Float = 0        // Shadow tone, -2...+4
    public var color: Float = 0         // Color (saturation), -4...+4
    public var chrome: Float = 0        // Color Chrome Effect: 0 off, 1 weak, 2 strong
    public var chromeBlue: Float = 0    // Color Chrome FX Blue: 0 off, 1 weak, 2 strong

    public init() {}
    public var isNeutral: Bool { self == Adjustments() }
}

/// A film-simulation recipe from the open-fuji-recipes community collection.
public struct Recipe: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let creator: String
    public let film: String
    public let sensor: Int
    public let lookID: String?
    public let grain: GrainAmount
    public let grainSize: GrainSize
    public let adjustments: Adjustments
    /// Short human summary, e.g. "Classic Chrome · Grain weak · H -1 S +2 · Color -2"
    public let summary: String

    public static func == (a: Recipe, b: Recipe) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }

    /// Settings this recipe produces (keeps the caller's camera and strength).
    public func apply(to settings: RenderSettings) -> RenderSettings {
        var s = settings
        if let lookID, let look = Looks.look(lookID), Looks.isInstalled(look, camera: s.camera) { s.look = look }
        s.grain = grain
        s.grainSize = grainSize
        s.adjustments = adjustments
        return s
    }
}

public enum Recipes {
    /// All bundled recipes (empty if there is no recipes.json).
    public static let all: [Recipe] = {
        guard let url = Looks.fileURL("recipes", ext: "json"), let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return raw.enumerated().compactMap { parse($1, id: $0) }
    }()

    /// Recipes made for a camera's sensor generation (all recipes for "any camera").
    public static func available(for camera: Camera?) -> [Recipe] {
        all.filter { r in
            guard let camera else { return true }
            guard r.sensor == camera.recipeSensor, let look = r.lookID else { return false }
            return camera.looks.contains(look)
        }
    }

    static let filmMap: [String: String] = [
        "PROVIA/Standard": "provia", "VELVIA/Vivid": "velvia", "ASTIA/Soft": "astia",
        "Classic Chrome": "classic-chrome", "Classic Neg": "classic-neg", "Pro Neg Hi": "pro-neg-hi",
        "Pro Neg Std": "pro-neg-std", "ETERNA/Cinema": "eterna", "ACROS": "acros", "ACROS +Y": "acros-ye",
        "ACROS +R": "acros-r", "ACROS +G": "acros-g", "MONOCHROME": "monochrome",
        "MONOCHROME +Y": "monochrome-ye", "MONOCHROME +R": "monochrome-r", "MONOCHROME +G": "monochrome-g",
        "SEPIA": "sepia",
    ]

    static func number(_ v: Any?) -> Float {
        if let n = v as? NSNumber { return n.floatValue }
        guard let s = (v as? String)?.replacingOccurrences(of: "+", with: "") else { return 0 }
        if let slash = s.firstIndex(of: "/") {  // "-1/3", "+2/3"
            let num = Float(s[..<slash]) ?? 0, den = Float(s[s.index(after: slash)...]) ?? 1
            return den == 0 ? 0 : num / den
        }
        return Float(s) ?? 0
    }

    static func level(_ v: Any?) -> Float {
        switch (v as? String)?.lowercased() {
        case "weak": return 1
        case "strong": return 2
        default: return 0
        }
    }

    static func parse(_ r: [String: Any], id: Int) -> Recipe? {
        guard let name = r["name"] as? String, let film = r["film"] as? String else { return nil }
        var a = Adjustments()
        a.exposure = number(r["ev"])
        a.wbRed = number(r["wbr"])
        a.wbBlue = number(r["wbb"])
        a.highlight = number(r["h-tone"])
        a.shadow = number(r["s-tone"])
        a.color = number(r["color"])
        a.chrome = level(r["ccfx"])
        a.chromeBlue = level(r["ccfxb"])
        switch (r["dr"] as? String)?.uppercased() {  // dynamic range: softer highlights
        case "DR200": a.highlight -= 0.75
        case "DR400": a.highlight -= 1.5
        case "WEAK": a.highlight -= 0.75; a.shadow -= 0.5      // D-Range Priority
        case "STRONG": a.highlight -= 1.5; a.shadow -= 1
        default: break
        }
        let g = (r["grain"] as? String ?? "off").lowercased()
        let grain: GrainAmount = g.hasPrefix("strong") ? .strong : g.hasPrefix("weak") ? .weak : .off
        let size: GrainSize = g.hasSuffix(" l") ? .large : .small
        let lookID = filmMap[film]

        func signed(_ x: Float) -> String { x > 0 ? "+\(fmt(x))" : fmt(x) }
        func fmt(_ x: Float) -> String { x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x) }
        var parts = [Looks.look(lookID ?? "")?.name ?? film]
        if grain != .off { parts.append("Grain \(grain.rawValue.lowercased())\(size == .large ? " L" : "")") }
        if a.chrome > 0 { parts.append("Chrome \(a.chrome == 1 ? "weak" : "strong")") }
        if a.chromeBlue > 0 { parts.append("FX Blue \(a.chromeBlue == 1 ? "weak" : "strong")") }
        let h = number(r["h-tone"]), s = number(r["s-tone"])
        if h != 0 || s != 0 { parts.append("H \(signed(h)) S \(signed(s))") }
        if a.color != 0 { parts.append("Color \(signed(a.color))") }
        if a.wbRed != 0 || a.wbBlue != 0 { parts.append("WB \(signed(a.wbRed))R \(signed(a.wbBlue))B") }
        if a.exposure != 0 { parts.append("EV \(signed(a.exposure))") }

        return Recipe(id: id, name: name, creator: r["creator"] as? String ?? "", film: film,
                      sensor: Int(number(r["sensor"])), lookID: lookID, grain: grain, grainSize: size,
                      adjustments: a, summary: parts.joined(separator: " · "))
    }
}
