import CoreGraphics
import Foundation

/// The settings that define one finished image.
public struct RenderSettings: Equatable, Sendable {
    public var look: Look?           // nil = original
    public var strength: Float = 1   // 0...1 mix between original and look
    public var grain: GrainAmount = .off
    public var grainSize: GrainSize = .small
    public var camera: Camera?       // nil = any camera (shared looks)
    public var adjustments = Adjustments()

    public init(look: Look? = Looks.look("classic-chrome"), strength: Float = 1,
                grain: GrainAmount = .off, grainSize: GrainSize = .small, camera: Camera? = nil) {
        self.look = look
        self.strength = strength
        self.grain = grain
        self.grainSize = grainSize
        self.camera = camera
    }
}

public enum Renderer {
    // MARK: CPU reference path (tests, parity checks, fallback when there is no GPU)

    /// Look only (the expensive LUT step).
    public static func applyLook(_ look: Look?, camera: Camera? = nil, to base: RGBImage) throws -> RGBImage {
        guard let look else { return base }
        return try Looks.lut(for: look, camera: camera).apply(to: base)
    }

    /// Mixes the look with the original by `strength`, then adds grain.
    public static func finish(base: RGBImage, looked: RGBImage, settings: RenderSettings, grain: GrainField?) -> RGBImage {
        var out = looked
        let s = settings.strength
        if s < 1 {
            base.pixels.withUnsafeBufferPointer { b in
                out.pixels.withUnsafeMutableBufferPointer { o in
                    for i in 0..<o.count { o[i] = b[i] + (o[i] - b[i]) * s }
                }
            }
        }
        if settings.grain != .off, let grain {
            grain.apply(to: &out, amount: settings.grain)
        }
        return out
    }

    /// CPU reference (look, strength, grain). Recipe adjustments are GPU-only.
    public static func renderCPU(_ base: RGBImage, settings: RenderSettings) throws -> RGBImage {
        let looked = try applyLook(settings.look, camera: settings.camera, to: base)
        let grain = settings.grain == .off ? nil
            : GrainField(width: base.width, height: base.height, size: settings.grainSize)
        return finish(base: base, looked: looked, settings: settings, grain: grain)
    }

    // MARK: full-resolution output

    /// Decodes `source` at full resolution, renders it (GPU when available) and returns the finished image.
    public static func render(_ source: PhotoSource, settings: RenderSettings) throws -> CGImage {
        let pixels = try PhotoIO.loadRGBA8(source)
        if let gpu = GPUEngine.shared {
            return try gpu.renderCGImage(gpu.upload(pixels), settings: settings)
        }
        return PhotoIO.cgImage(from: try renderCPU(PhotoIO.rgbImage(from: pixels), settings: settings))
    }

    /// Full-resolution JPEG with the source's EXIF (date, camera, location) kept.
    public static func jpegData(_ source: PhotoSource, settings: RenderSettings) throws -> Data {
        try PhotoIO.jpegData(render(source, settings: settings), metadata: PhotoIO.exportMetadata(from: source))
    }

    /// Renders `source` and writes `<name>_<look>.jpg` into `folder` (never overwriting).
    @discardableResult
    public static func export(_ source: URL, settings: RenderSettings, to folder: URL) throws -> URL {
        let data = try jpegData(.url(source), settings: settings)
        let stem = source.deletingPathExtension().lastPathComponent
        let suffix = settings.look?.id ?? "original"
        var url = folder.appendingPathComponent("\(stem)_\(suffix).jpg")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stem)_\(suffix)_\(n).jpg")
            n += 1
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}
