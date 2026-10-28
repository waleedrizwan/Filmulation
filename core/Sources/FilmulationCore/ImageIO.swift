import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageIOError: Error, CustomStringConvertible {
    case unreadable(String)
    case cannotWrite(String)
    public var description: String {
        switch self {
        case .unreadable(let n): return "Can't read \(n)"
        case .cannotWrite(let n): return "Can't write \(n)"
        }
    }
}

/// Where a photo comes from: a file (Mac) or in-memory data (iPhone photo library).
public enum PhotoSource: Sendable {
    case url(URL)
    case data(Data, name: String)

    var name: String {
        switch self {
        case .url(let u): return u.lastPathComponent
        case .data(_, let n): return n
        }
    }

    func imageSource() throws -> CGImageSource {
        let src: CGImageSource?
        switch self {
        case .url(let u): src = CGImageSourceCreateWithURL(u as CFURL, nil)
        case .data(let d, _): src = CGImageSourceCreateWithData(d as CFData, nil)
        }
        guard let src else { throw ImageIOError.unreadable(name) }
        return src
    }
}

/// 8-bit RGBA (alpha ignored) image in sRGB, the GPU engine's input and output format.
public struct RGBA8Image: Sendable {
    public let width: Int
    public let height: Int
    public var bytes: [UInt8]

    /// A copy of the rectangle at (x, y).
    func crop(x: Int, y: Int, width w: Int, height h: Int) -> RGBA8Image {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for row in 0..<h {
            let src = ((y + row) * width + x) * 4
            out.replaceSubrange((row * w * 4)..<((row + 1) * w * 4), with: bytes[src..<(src + w * 4)])
        }
        return RGBA8Image(width: w, height: h, bytes: out)
    }

    /// Copies `image` in with its top-left corner at (x, y).
    mutating func paste(_ image: RGBA8Image, x: Int, y: Int) {
        let w = image.width
        for row in 0..<image.height {
            let dst = ((y + row) * width + x) * 4
            bytes.replaceSubrange(dst..<(dst + w * 4), with: image.bytes[(row * w * 4)..<((row + 1) * w * 4)])
        }
    }
}

public enum PhotoIO {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    public static let supportedTypes: [UTType] = [.jpeg, .png, .heic, .heif, .tiff, .webP]

    /// Decodes a photo, applies its EXIF orientation and optionally downsizes so the long side is <= maxPixelSize.
    public static func decode(_ source: PhotoSource, maxPixelSize: Int? = nil) throws -> CGImage {
        let src = try source.imageSource()
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            throw ImageIOError.unreadable(source.name)
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize.map { min($0, max(w, h)) } ?? max(w, h),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw ImageIOError.unreadable(source.name)
        }
        return cg
    }

    /// Decode straight to sRGB RGBA8; Core Graphics converts from the embedded profile (e.g. iPhone Display P3).
    public static func loadRGBA8(_ source: PhotoSource, maxPixelSize: Int? = nil) throws -> RGBA8Image {
        rgba8(from: try decode(source, maxPixelSize: maxPixelSize))
    }

    public static func load(_ url: URL, maxPixelSize: Int? = nil) throws -> RGBImage {
        rgbImage(from: try loadRGBA8(.url(url), maxPixelSize: maxPixelSize))
    }

    public static func rgba8(from cg: CGImage) -> RGBA8Image {
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return RGBA8Image(width: w, height: h, bytes: bytes)
    }

    public static func rgbImage(from img: RGBA8Image) -> RGBImage {
        var px = [Float](repeating: 0, count: img.width * img.height * 3)
        for i in 0..<(img.width * img.height) {
            px[i * 3] = Float(img.bytes[i * 4]) / 255
            px[i * 3 + 1] = Float(img.bytes[i * 4 + 1]) / 255
            px[i * 3 + 2] = Float(img.bytes[i * 4 + 2]) / 255
        }
        return RGBImage(width: img.width, height: img.height, pixels: px)
    }

    public static func cgImage(from image: RGBA8Image) -> CGImage {
        let provider = CGDataProvider(data: Data(image.bytes) as CFData)!
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.width * 4, space: sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// 8-bit sRGB CGImage from the float (CPU) pipeline.
    public static func cgImage(from image: RGBImage) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: image.width * image.height * 4)
        image.pixels.withUnsafeBufferPointer { p in
            for i in 0..<(image.width * image.height) {
                bytes[i * 4] = UInt8(min(max(p[i * 3], 0), 1) * 255 + 0.5)
                bytes[i * 4 + 1] = UInt8(min(max(p[i * 3 + 1], 0), 1) * 255 + 0.5)
                bytes[i * 4 + 2] = UInt8(min(max(p[i * 3 + 2], 0), 1) * 255 + 0.5)
            }
        }
        return cgImage(from: RGBA8Image(width: image.width, height: image.height, bytes: bytes))
    }

    /// EXIF/GPS/TIFF metadata of the source, with orientation reset (pixels are already upright).
    public static func exportMetadata(from source: PhotoSource?) -> [CFString: Any] {
        var props: [CFString: Any] = [:]
        if let source, let src = try? source.imageSource(),
           let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary] {
                if let v = p[key] { props[key] = v }
            }
            if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                tiff[kCGImagePropertyTIFFSoftware] = "Filmulation"
                props[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        props[kCGImagePropertyOrientation] = 1
        return props
    }

    /// JPEG bytes with an sRGB image and the given metadata.
    public static func jpegData(_ cg: CGImage, metadata: [CFString: Any], quality: Double = 0.93) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageIOError.cannotWrite("JPEG")
        }
        var props = metadata
        props[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageIOError.cannotWrite("JPEG") }
        return data as Data
    }

    public static func writeJPEG(_ cg: CGImage, to url: URL, metadataFrom source: PhotoSource?, quality: Double = 0.93) throws {
        try jpegData(cg, metadata: exportMetadata(from: source), quality: quality).write(to: url, options: .atomic)
    }

    public static func writeJPEG(_ image: RGBImage, to url: URL, metadataFrom source: URL?, quality: Double = 0.93) throws {
        try writeJPEG(cgImage(from: image), to: url, metadataFrom: source.map { .url($0) }, quality: quality)
    }
}
