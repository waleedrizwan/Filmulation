import Foundation

/// A film look backed by a baked sRGB -> sRGB LUT.
public struct Look: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let blurb: String
    public var isBlackAndWhite: Bool { Looks.blackAndWhite.contains(id) }
}

public enum Looks {
    public static let all: [Look] = [
        Look(id: "provia", name: "Provia",
             blurb: "Fuji's standard. Balanced, true-to-life colour; closest to your original."),
        Look(id: "velvia", name: "Velvia",
             blurb: "Vivid slide film. Rich saturation and contrast; great for landscapes and skies."),
        Look(id: "astia", name: "Astia",
             blurb: "Soft slide film. Gentle contrast and flattering skin tones; good for portraits."),
        Look(id: "classic-chrome", name: "Classic Chrome",
             blurb: "Muted, cooler colour with strong shadows. Documentary / street-photo look."),
        Look(id: "reala-ace", name: "Reala Ace",
             blurb: "Faithful colour with a touch more depth and contrast than Provia."),
        Look(id: "pro-neg-hi", name: "Pro Neg Hi",
             blurb: "Portrait negative film with more punch. Natural skin, a bit more contrast."),
        Look(id: "pro-neg-std", name: "Pro Neg Std",
             blurb: "Portrait negative film. Very soft and natural; smooth skin, low contrast."),
        Look(id: "classic-neg", name: "Classic Neg",
             blurb: "Everyday colour negative film. Hard contrast, teal-green shifts, nostalgic feel."),
        Look(id: "nostalgic-neg", name: "Nostalgic Neg",
             blurb: "Warm, amber highlights and rich shadows, like 1970s American colour prints."),
        Look(id: "eterna", name: "Eterna",
             blurb: "Cinema film. Low saturation and soft contrast; moody, movie-like."),
        Look(id: "eterna-bb", name: "Bleach Bypass",
             blurb: "Washed-out colour with harsh contrast. Gritty, dramatic film look."),
        Look(id: "acros", name: "Acros",
             blurb: "Black & white film. Fine detail, deep blacks and smooth greys."),
        Look(id: "acros-ye", name: "Acros + Yellow",
             blurb: "Acros with a yellow filter: slightly darker skies, a touch more contrast."),
        Look(id: "acros-r", name: "Acros + Red",
             blurb: "Acros with a red filter: dramatic dark skies, bright skin and reds."),
        Look(id: "acros-g", name: "Acros + Green",
             blurb: "Acros with a green filter: richer skin tones and lighter foliage."),
        Look(id: "monochrome", name: "Monochrome",
             blurb: "Plain black & white with standard contrast."),
        Look(id: "monochrome-ye", name: "Mono + Yellow",
             blurb: "Black & white with a yellow filter: slightly darker skies."),
        Look(id: "monochrome-r", name: "Mono + Red",
             blurb: "Black & white with a red filter: dark skies, bright reds."),
        Look(id: "monochrome-g", name: "Mono + Green",
             blurb: "Black & white with a green filter: lighter foliage, richer skin."),
        Look(id: "sepia", name: "Sepia",
             blurb: "Warm brown-toned monochrome, like an old print."),
    ]

    static let blackAndWhite: Set<String> = ["acros", "acros-ye", "acros-r", "acros-g", "monochrome",
                                             "monochrome-ye", "monochrome-r", "monochrome-g", "sepia"]

    public static func look(_ id: String) -> Look? { all.first { $0.id == id } }

    /// Looks for a camera (all for "any camera"), skipping any whose file wasn't generated.
    public static func available(for camera: Camera?) -> [Look] {
        all.filter { (camera?.looks.contains($0.id) ?? true) && fileURL(lutFile(for: $0, camera: camera)) != nil }
    }

    /// File stem of the LUT for a look on a camera: the camera's own Eterna / Bleach Bypass when Fujifilm
    /// publishes one, otherwise the shared look.
    public static func lutFile(for look: Look, camera: Camera?) -> String {
        if let pack = camera?.lutPack, let stem = cameraLUTs[pack]?[look.id], fileURL(stem) != nil { return stem }
        return look.id
    }

    private static let cache = LUTCache()

    /// Loads (and caches) the LUT for a look from the bundled resources.
    public static func lut(for look: Look, camera: Camera? = nil) throws -> CubeLUT {
        let stem = lutFile(for: look, camera: camera)
        return try cache.lut(stem) {
            guard let url = fileURL(stem) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "LUTs/\(stem).lut — no look files installed"])
            }
            return try CubeLUT(binaryContentsOf: url)
        }
    }

    /// Inside Filmulation.app the LUTs live in Contents/Resources/LUTs (see build_app.sh);
    /// otherwise they come from the SwiftPM resource bundle.
    static func fileURL(_ name: String, ext: String = "lut") -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "LUTs")
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "LUTs")
    }

    /// camera pack id -> look id -> LUT file stem (optional camera_luts.json)
    static let cameraLUTs: [String: [String: String]] = {
        guard let url = fileURL("camera_luts", ext: "json"), let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
    }()
}

private final class LUTCache: @unchecked Sendable {
    private var luts: [String: CubeLUT] = [:]
    private let lock = NSLock()

    func lut(_ id: String, load: () throws -> CubeLUT) throws -> CubeLUT {
        lock.lock()
        defer { lock.unlock() }
        if let l = luts[id] { return l }
        let l = try load()
        luts[id] = l
        return l
    }
}
