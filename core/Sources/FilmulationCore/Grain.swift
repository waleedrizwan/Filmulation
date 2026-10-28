import Foundation

public enum GrainAmount: String, CaseIterable, Identifiable, Sendable {
    case off = "Off", weak = "Weak", strong = "Strong"
    public var id: String { rawValue }
    /// Grain strength in sRGB units at mid-grey.
    var strength: Float {
        switch self {
        case .off: return 0
        case .weak: return 0.028
        case .strong: return 0.048
        }
    }
}

public enum GrainSize: String, CaseIterable, Identifiable, Sendable {
    case small = "Small", large = "Large"
    public var id: String { rawValue }
    var factor: Float { self == .small ? 1.0 : 1.8 }
}

/// Monochrome film grain: three octaves of blurred Gaussian noise (after darktable's grain module),
/// normalised to unit standard deviation. Sized relative to a 3000 px long side so preview and export match.
public struct GrainField: Sendable {
    public let width: Int
    public let height: Int
    let values: [Float]

    public init(width: Int, height: Int, size: GrainSize, seed: UInt64 = 1) {
        self.width = width
        self.height = height
        let scale = Float(max(width, height)) / 3000 * size.factor
        var field = [Float](repeating: 0, count: width * height)
        var rng = SplitMix64(seed: seed)
        for (rel, amp) in [(Float(0.5), Float(0.234)), (1.0, 0.785), (2.0, 1.215)] {
            var n = gaussianNoise(count: width * height, rng: &rng)
            gaussianBlur(&n, width: width, height: height, sigma: max(scale * rel, 0.35))
            let sd = standardDeviation(n)
            for i in 0..<n.count { field[i] += amp * n[i] / (sd + 1e-8) }
        }
        let sd = standardDeviation(field)
        for i in 0..<field.count { field[i] /= sd }
        values = field
    }

    /// Adds grain to luminance, fading it in deep shadows and bright highlights like film's paper response.
    public func apply(to image: inout RGBImage, amount: GrainAmount) {
        precondition(image.width == width && image.height == height)
        let strength = amount.strength
        guard strength > 0 else { return }
        values.withUnsafeBufferPointer { gv in
            image.pixels.withUnsafeMutableBufferPointer { px in
                let g = gv, p = px, w = width
                parallelRows(height) { y0, y1 in
                    for i in (y0 * w)..<(y1 * w) {
                        let o = i * 3
                        let luma = 0.2126 * p[o] + 0.7152 * p[o + 1] + 0.0722 * p[o + 2]
                        let response = powf(min(max(4 * luma * (1 - luma), 0), 1), 0.7)
                        let delta = strength * response * g[i]
                        p[o] += delta; p[o + 1] += delta; p[o + 2] += delta
                    }
                }
            }
        }
    }
}

struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
}

func gaussianNoise(count: Int, rng: inout SplitMix64) -> [Float] {
    var out = [Float](repeating: 0, count: count)
    var i = 0
    while i < count {  // Box-Muller, two samples per pair of uniforms
        let u1 = max(rng.unit(), 1e-7), u2 = rng.unit()
        let r = sqrtf(-2 * logf(u1)), a = 2 * Float.pi * u2
        out[i] = r * cosf(a)
        if i + 1 < count { out[i + 1] = r * sinf(a) }
        i += 2
    }
    return out
}

func standardDeviation(_ v: [Float]) -> Float {
    let mean = v.reduce(0, +) / Float(v.count)
    let variance = v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(v.count)
    return sqrtf(variance)
}

/// Separable Gaussian blur of a single-channel image, edges clamped.
func gaussianBlur(_ data: inout [Float], width: Int, height: Int, sigma: Float) {
    let radius = max(1, Int(ceilf(sigma * 3)))
    var kernel = (-radius...radius).map { expf(-Float($0 * $0) / (2 * sigma * sigma)) }
    let total = kernel.reduce(0, +)
    kernel = kernel.map { $0 / total }
    var tmp = [Float](repeating: 0, count: data.count)
    kernel.withUnsafeBufferPointer { kp in
        data.withUnsafeBufferPointer { src in
            tmp.withUnsafeMutableBufferPointer { dst in
                let k = kp, s = src, d = dst
                parallelRows(height) { y0, y1 in
                    for y in y0..<y1 {
                        for x in 0..<width {
                            var acc: Float = 0
                            for j in -radius...radius {
                                acc += k[j + radius] * s[y * width + min(max(x + j, 0), width - 1)]
                            }
                            d[y * width + x] = acc
                        }
                    }
                }
            }
        }
        tmp.withUnsafeBufferPointer { src in
            data.withUnsafeMutableBufferPointer { dst in
                let k = kp, s = src, d = dst
                parallelRows(height) { y0, y1 in
                    for y in y0..<y1 {
                        for x in 0..<width {
                            var acc: Float = 0
                            for j in -radius...radius {
                                acc += k[j + radius] * s[min(max(y + j, 0), height - 1) * width + x]
                            }
                            d[y * width + x] = acc
                        }
                    }
                }
            }
        }
    }
}
