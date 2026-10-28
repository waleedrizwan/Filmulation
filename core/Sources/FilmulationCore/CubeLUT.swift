import Foundation

public enum CubeLUTError: Error, CustomStringConvertible {
    case missingSize(URL)
    case wrongCount(URL, expected: Int, got: Int)
    case unsupported(URL, String)

    public var description: String {
        switch self {
        case .missingSize(let u): return "\(u.lastPathComponent): no LUT_3D_SIZE"
        case .wrongCount(let u, let e, let g): return "\(u.lastPathComponent): expected \(e) entries, got \(g)"
        case .unsupported(let u, let what): return "\(u.lastPathComponent): \(what) not supported"
        }
    }
}

/// A 3D LUT from a .cube file (red varies fastest), applied with tetrahedral interpolation.
public final class CubeLUT: Sendable {
    public let size: Int
    /// size³ RGB triplets, index = ((b * size) + g) * size + r
    public let table: [Float]

    public init(size: Int, table: [Float]) {
        precondition(table.count == size * size * size * 3)
        self.size = size
        self.table = table
    }

    public convenience init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var size = 0
        var values: [Float] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let first = line.first, first != "#" else { continue }
            if line.hasPrefix("LUT_3D_SIZE") {
                size = Int(line.split(separator: " ").last ?? "") ?? 0
                values.reserveCapacity(size * size * size * 3)
            } else if line.hasPrefix("LUT_1D_SIZE") {
                throw CubeLUTError.unsupported(url, "1D LUT")
            } else if line.hasPrefix("DOMAIN_MAX") {
                if line.split(separator: " ").dropFirst().contains(where: { Float($0) != 1 }) {
                    throw CubeLUTError.unsupported(url, "non-unit DOMAIN_MAX")
                }
            } else if first.isNumber || first == "-" || first == "." {
                for v in line.split(separator: " ").prefix(3) { values.append(Float(v) ?? 0) }
            }
        }
        guard size > 1 else { throw CubeLUTError.missingSize(url) }
        guard values.count == size * size * size * 3 else {
            throw CubeLUTError.wrongCount(url, expected: size * size * size * 3, got: values.count)
        }
        self.init(size: size, table: values)
    }

    /// Binary LUT: little-endian UInt32 size, then size³ RGB Float32 (red fastest).
    public convenience init(binaryContentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 4 else { throw CubeLUTError.missingSize(url) }
        let n = Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        let count = n * n * n * 3
        guard n > 1, data.count == 4 + count * 4 else {
            throw CubeLUTError.wrongCount(url, expected: 4 + count * 4, got: data.count)
        }
        let table = data.withUnsafeBytes { raw in
            Array(UnsafeBufferPointer(start: raw.baseAddress!.advanced(by: 4).assumingMemoryBound(to: Float.self),
                                      count: count))
        }
        self.init(size: n, table: table)
    }

    /// Returns a new image with the LUT applied to every pixel.
    public func apply(to image: RGBImage) -> RGBImage {
        var out = RGBImage(width: image.width, height: image.height)
        let w = image.width
        image.pixels.withUnsafeBufferPointer { src in
            out.pixels.withUnsafeMutableBufferPointer { dst in
                let s = src, d = dst
                table.withUnsafeBufferPointer { t in
                    let tab = t
                    parallelRows(image.height) { y0, y1 in
                        for i in (y0 * w)..<(y1 * w) {
                            let o = i * 3
                            lookup(tab, s[o], s[o + 1], s[o + 2], into: d, at: o)
                        }
                    }
                }
            }
        }
        return out
    }

    @inline(__always)
    private func lookup(_ t: UnsafeBufferPointer<Float>, _ r: Float, _ g: Float, _ b: Float,
                        into d: UnsafeMutableBufferPointer<Float>, at o: Int) {
        let n = size
        let m = Float(n - 1)
        let x = min(max(r, 0), 1) * m, y = min(max(g, 0), 1) * m, z = min(max(b, 0), 1) * m
        let r0 = min(Int(x), n - 2), g0 = min(Int(y), n - 2), b0 = min(Int(z), n - 2)
        let fr = x - Float(r0), fg = y - Float(g0), fb = z - Float(b0)
        @inline(__always) func idx(_ dr: Int, _ dg: Int, _ db: Int) -> Int {
            (((b0 + db) * n + (g0 + dg)) * n + (r0 + dr)) * 3
        }
        // pick the tetrahedron by the ordering of the fractional parts
        let c000 = idx(0, 0, 0), c111 = idx(1, 1, 1)
        let a: Int, bb: Int, w1: Float, w2: Float, w3: Float
        if fr >= fg {
            if fg >= fb { a = idx(1, 0, 0); bb = idx(1, 1, 0); w1 = fr; w2 = fg; w3 = fb }
            else if fr >= fb { a = idx(1, 0, 0); bb = idx(1, 0, 1); w1 = fr; w2 = fb; w3 = fg }
            else { a = idx(0, 0, 1); bb = idx(1, 0, 1); w1 = fb; w2 = fr; w3 = fg }
        } else {
            if fb >= fg { a = idx(0, 0, 1); bb = idx(0, 1, 1); w1 = fb; w2 = fg; w3 = fr }
            else if fb >= fr { a = idx(0, 1, 0); bb = idx(0, 1, 1); w1 = fg; w2 = fb; w3 = fr }
            else { a = idx(0, 1, 0); bb = idx(1, 1, 0); w1 = fg; w2 = fr; w3 = fb }
        }
        let k0 = 1 - w1, k1 = w1 - w2, k2 = w2 - w3
        for c in 0..<3 {
            d[o + c] = k0 * t[c000 + c] + k1 * t[a + c] + k2 * t[bb + c] + w3 * t[c111 + c]
        }
    }
}
