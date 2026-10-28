import CoreGraphics
import Foundation
import Metal

public enum GPUEngineError: Error, CustomStringConvertible {
    case tooLarge(width: Int, height: Int, max: Int)
    case cannotAllocate(width: Int, height: Int)

    public var description: String {
        switch self {
        case .tooLarge(let w, let h, let max): return "\(w)×\(h) is larger than the GPU's \(max) px limit"
        case .cannotAllocate(let w, let h): return "not enough GPU memory for a \(w)×\(h) image"
        }
    }
}

/// A photo uploaded to the GPU once, then rendered with any settings in a few milliseconds.
public final class GPUImage: @unchecked Sendable {
    public let width: Int
    public let height: Int
    let texture: MTLTexture

    init(texture: MTLTexture) {
        self.texture = texture
        width = texture.width
        height = texture.height
    }
}

/// The whole look (3D LUT, strength mix and film grain) in one Metal compute pass.
/// Matches the CPU path (CubeLUT + GrainField) in look; the grain is generated procedurally on the GPU.
public final class GPUEngine: @unchecked Sendable {
    public static let shared: GPUEngine? = try? GPUEngine()

    /// Side length of the tiles that photos too big for one texture are rendered in.
    static let tileSize = 8192

    let device: MTLDevice
    /// Largest texture width or height this GPU accepts; `upload` refuses anything bigger.
    public let maxTextureSize: Int
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let identityLUT: MTLTexture
    private var luts: [String: MTLTexture] = [:]
    private let lock = NSLock()

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw CocoaError(.featureUnsupported)
        }
        self.device = device
        self.queue = queue
        // Apple-silicon and Mac GPUs take 16384 px textures; older iOS GPUs only 8192
        maxTextureSize = device.supportsFamily(.apple3) || device.supportsFamily(.mac2) ? 16384 : 8192
        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "film")!)
        identityLUT = try Self.makeLUTTexture(device: device, size: 2, table: [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0,
                                                                              0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1])
    }

    /// Uploads a photo that fits in one texture (see `maxTextureSize`); use `render(_: RGBA8Image, ...)` for any size.
    public func upload(_ image: RGBA8Image) throws -> GPUImage {
        let tex = try makeTexture(width: image.width, height: image.height, usage: .shaderRead)
        image.bytes.withUnsafeBytes { buf in
            tex.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                        withBytes: buf.baseAddress!, bytesPerRow: image.width * 4)
        }
        return GPUImage(texture: tex)
    }

    private func makeTexture(width: Int, height: Int, usage: MTLTextureUsage) throws -> MTLTexture {
        guard width <= maxTextureSize, height <= maxTextureSize else {
            throw GPUEngineError.tooLarge(width: width, height: height, max: maxTextureSize)
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height,
                                                            mipmapped: false)
        desc.usage = usage
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else {
            throw GPUEngineError.cannotAllocate(width: width, height: height)
        }
        return tex
    }

    /// Loads all look LUTs onto the GPU ahead of time so the first tap is instant.
    public func preloadLooks(camera: Camera? = nil) {
        for look in Looks.available(for: camera) { _ = try? lutTexture(for: look, camera: camera) }
    }

    func lutTexture(for look: Look, camera: Camera?) throws -> MTLTexture {
        let stem = Looks.lutFile(for: look, camera: camera)
        lock.lock()
        if let t = luts[stem] { lock.unlock(); return t }
        lock.unlock()
        let cube = try Looks.lut(for: look, camera: camera)
        let tex = try Self.makeLUTTexture(device: device, size: cube.size, table: cube.table)
        lock.lock()
        luts[stem] = tex
        lock.unlock()
        return tex
    }

    static func makeLUTTexture(device: MTLDevice, size n: Int, table: [Float]) throws -> MTLTexture {
        let desc = MTLTextureDescriptor()
        desc.textureType = .type3D
        desc.pixelFormat = .rgba32Float
        desc.width = n; desc.height = n; desc.depth = n
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { throw GPUEngineError.cannotAllocate(width: n, height: n) }
        var rgba = [Float](repeating: 1, count: n * n * n * 4)
        for i in 0..<(n * n * n) {
            rgba[i * 4] = table[i * 3]; rgba[i * 4 + 1] = table[i * 3 + 1]; rgba[i * 4 + 2] = table[i * 3 + 2]
        }
        rgba.withUnsafeBytes { buf in
            tex.replace(region: MTLRegionMake3D(0, 0, 0, n, n, n), mipmapLevel: 0, slice: 0,
                        withBytes: buf.baseAddress!, bytesPerRow: n * 16, bytesPerImage: n * n * 16)
        }
        return tex
    }

    /// Renders `image` with `settings` and returns 8-bit sRGB pixels.
    public func render(_ image: GPUImage, settings: RenderSettings, seed: UInt32 = 1) throws -> RGBA8Image {
        try render(image, settings: settings, seed: seed, origin: (0, 0),
                   fullSize: (image.width, image.height))
    }

    /// Renders a photo of any size: in one pass when it fits in a texture, otherwise tile by tile.
    /// Tiles give exactly the same pixels as one pass (the grain follows the position in the whole photo).
    public func render(_ image: RGBA8Image, settings: RenderSettings, seed: UInt32 = 1) throws -> RGBA8Image {
        try render(image, settings: settings, seed: seed, tileSize: Self.tileSize)
    }

    func render(_ image: RGBA8Image, settings: RenderSettings, seed: UInt32, tileSize: Int,
                forceTiles: Bool = false) throws -> RGBA8Image {
        if !forceTiles, image.width <= maxTextureSize, image.height <= maxTextureSize {
            return try render(upload(image), settings: settings, seed: seed)
        }
        var out = RGBA8Image(width: image.width, height: image.height,
                             bytes: [UInt8](repeating: 0, count: image.bytes.count))
        for y in stride(from: 0, to: image.height, by: tileSize) {
            for x in stride(from: 0, to: image.width, by: tileSize) {
                let tile = image.crop(x: x, y: y, width: min(tileSize, image.width - x),
                                      height: min(tileSize, image.height - y))
                let done = try render(upload(tile), settings: settings, seed: seed, origin: (x, y),
                                      fullSize: (image.width, image.height))
                out.paste(done, x: x, y: y)
            }
        }
        return out
    }

    /// One pass over `image`, which sits at `origin` in a photo of `fullSize` (for grain size and position).
    private func render(_ image: GPUImage, settings: RenderSettings, seed: UInt32, origin: (x: Int, y: Int),
                        fullSize: (width: Int, height: Int)) throws -> RGBA8Image {
        let out = try makeTexture(width: image.width, height: image.height, usage: .shaderWrite)

        let a = settings.adjustments
        var params = Params(
            strength: settings.look == nil && a.isNeutral ? 0 : settings.strength,
            grainStrength: settings.grain.strength,
            grainScale: Float(max(fullSize.width, fullSize.height)) / 3000 * settings.grainSize.factor,
            exposure: a.exposure, wbRed: a.wbRed, wbBlue: a.wbBlue, highlight: a.highlight, shadow: a.shadow,
            color: a.color, chrome: a.chrome, chromeBlue: a.chromeBlue,
            seed: seed, originX: UInt32(origin.x), originY: UInt32(origin.y))
        // At zero strength the look isn't used, so don't require its file
        let lut = params.strength > 0
            ? try settings.look.map { try lutTexture(for: $0, camera: settings.camera) } ?? identityLUT
            : identityLUT

        guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else {
            throw CocoaError(.featureUnsupported)
        }
        enc.setComputePipelineState(pipeline)
        enc.setTexture(image.texture, index: 0)
        enc.setTexture(lut, index: 1)
        enc.setTexture(out, index: 2)
        enc.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        enc.dispatchThreads(MTLSize(width: image.width, height: image.height, depth: 1), threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        if let err = cmd.error { throw err }

        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buf in
            out.getBytes(buf.baseAddress!, bytesPerRow: image.width * 4,
                         from: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0)
        }
        return RGBA8Image(width: image.width, height: image.height, bytes: bytes)
    }

    public func renderCGImage(_ image: GPUImage, settings: RenderSettings) throws -> CGImage {
        PhotoIO.cgImage(from: try render(image, settings: settings))
    }

    struct Params {
        var strength: Float
        var grainStrength: Float
        var grainScale: Float
        var exposure: Float
        var wbRed: Float
        var wbBlue: Float
        var highlight: Float
        var shadow: Float
        var color: Float
        var chrome: Float
        var chromeBlue: Float
        var seed: UInt32
        var originX: UInt32
        var originY: UInt32
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Params {
        float strength; float grainStrength; float grainScale;
        float exposure; float wbRed; float wbBlue; float highlight; float shadow;
        float color; float chrome; float chromeBlue;
        uint seed; uint originX; uint originY;
    };

    static float3 toLinear(float3 c) {
        return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
    }
    static float3 toSRGB(float3 c) {
        c = max(c, 0.0);
        return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
    }

    // Recipe settings that act on the scene before the film look: exposure and white-balance shift
    static float3 preLook(float3 c, constant Params& p) {
        if (p.exposure == 0.0 && p.wbRed == 0.0 && p.wbBlue == 0.0) return c;
        float3 lin = toLinear(c) * exp2(p.exposure);
        lin *= float3(1.0 + 0.03 * p.wbRed, 1.0, 1.0 + 0.03 * p.wbBlue);
        return saturate(toSRGB(lin));
    }

    // Recipe settings that shape the film look's output: tone, colour, Color Chrome
    static float3 postLook(float3 o, constant Params& p) {
        float y = dot(o, float3(0.2126, 0.7152, 0.0722));
        // Highlight / Shadow tone: + is harder (brighter highlights / deeper shadows), - is softer
        float d = 0.0;
        if (y > 0.5) d = 0.045 * p.highlight * 4.0 * (y - 0.5) * (1.0 - y);
        else         d = -0.045 * p.shadow * 4.0 * (0.5 - y) * y;
        o += d;
        y += d;
        // Color: saturation around luminance, about 7% per step
        o = y + (o - y) * max(0.0, 1.0 + 0.07 * p.color);
        // Color Chrome: deepen (darken) highly saturated colours; FX Blue does the same for blues
        float sat = max(o.r, max(o.g, o.b)) - min(o.r, min(o.g, o.b));
        if (p.chrome > 0.0) o *= 1.0 - 0.07 * p.chrome * sat * sat;
        if (p.chromeBlue > 0.0) {
            float blue = saturate((o.b - max(o.r, o.g)) * 3.0);
            o *= 1.0 - 0.08 * p.chromeBlue * blue * sat;
        }
        return o;
    }

    // Tetrahedral interpolation in a 3D LUT (same as CubeLUT.swift)
    static float3 lutLookup(texture3d<float, access::read> lut, float3 c) {
        int n = int(lut.get_width());
        float3 x = clamp(c, 0.0, 1.0) * float(n - 1);
        int3 i0 = min(int3(x), int3(n - 2));
        float3 f = x - float3(i0);
        uint3 b = uint3(i0);
        float3 c000 = lut.read(b).rgb;
        float3 c111 = lut.read(b + uint3(1, 1, 1)).rgb;
        uint3 a, bb; float w1, w2, w3;
        if (f.r >= f.g) {
            if (f.g >= f.b)      { a = uint3(1,0,0); bb = uint3(1,1,0); w1 = f.r; w2 = f.g; w3 = f.b; }
            else if (f.r >= f.b) { a = uint3(1,0,0); bb = uint3(1,0,1); w1 = f.r; w2 = f.b; w3 = f.g; }
            else                 { a = uint3(0,0,1); bb = uint3(1,0,1); w1 = f.b; w2 = f.r; w3 = f.g; }
        } else {
            if (f.b >= f.g)      { a = uint3(0,0,1); bb = uint3(0,1,1); w1 = f.b; w2 = f.g; w3 = f.r; }
            else if (f.b >= f.r) { a = uint3(0,1,0); bb = uint3(0,1,1); w1 = f.g; w2 = f.b; w3 = f.r; }
            else                 { a = uint3(0,1,0); bb = uint3(1,1,0); w1 = f.g; w2 = f.r; w3 = f.b; }
        }
        return (1.0 - w1) * c000 + (w1 - w2) * lut.read(b + a).rgb + (w2 - w3) * lut.read(b + bb).rgb + w3 * c111;
    }

    static uint hash3(uint x, uint y, uint z) {
        uint h = x * 0x8da6b343u ^ y * 0xd8163841u ^ z * 0xcb1ab31fu;
        h ^= h >> 16; h *= 0x7feb352du; h ^= h >> 15; h *= 0x846ca68bu; h ^= h >> 16;
        return h;
    }

    // Unit-variance value noise with cells of `cell` pixels (smoothstep-interpolated lattice values)
    static float valueNoise(float2 p, float cell, uint seed) {
        float2 q = p / cell;
        float2 i = floor(q);
        float2 t = q - i;
        float2 s = t * t * (3.0 - 2.0 * t);
        int2 k = int2(i);
        float v[4];
        for (int j = 0; j < 4; j++) {
            uint h = hash3(uint(k.x + (j & 1)), uint(k.y + (j >> 1)), seed);
            v[j] = (float(h) / 4294967295.0 * 2.0 - 1.0) * 1.7320508;   // uniform, unit variance
        }
        float n = mix(mix(v[0], v[1], s.x), mix(v[2], v[3], s.x), s.y);
        return cell <= 1.0 ? n : n * 1.3461515;   // undo the variance lost to interpolation
    }

    // Three octaves (darktable grain amplitudes), unit standard deviation
    static float grain(float2 p, float scale, uint seed) {
        float n = 0.234 * valueNoise(p, max(1.0, 2.0 * max(scale * 0.5, 0.35)), seed * 3u + 0u)
                + 0.785 * valueNoise(p, max(1.0, 2.0 * max(scale * 1.0, 0.35)), seed * 3u + 1u)
                + 1.215 * valueNoise(p, max(1.0, 2.0 * max(scale * 2.0, 0.35)), seed * 3u + 2u);
        return n / 1.4794;   // sqrt(0.234^2 + 0.785^2 + 1.215^2)
    }

    kernel void film(texture2d<float, access::read> src [[texture(0)]],
                     texture3d<float, access::read> lut [[texture(1)]],
                     texture2d<float, access::write> dst [[texture(2)]],
                     constant Params& p [[buffer(0)]],
                     uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
        float3 c = src.read(gid).rgb;
        float3 o = c;
        if (p.strength > 0.0) {
            float3 looked = postLook(lutLookup(lut, preLook(c, p)), p);
            o = mix(c, looked, p.strength);
        }
        if (p.grainStrength > 0.0) {
            float luma = dot(o, float3(0.2126, 0.7152, 0.0722));
            float response = pow(clamp(4.0 * luma * (1.0 - luma), 0.0, 1.0), 0.7);
            float2 pos = float2(gid) + float2(p.originX, p.originY);   // position in the whole photo
            o += p.grainStrength * response * grain(pos, p.grainScale, p.seed);
        }
        dst.write(float4(saturate(o), 1.0), gid);
    }
    """
}
