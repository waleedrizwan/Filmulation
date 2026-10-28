import Foundation

/// Interleaved RGB float image in sRGB-encoded 0...1 values.
public struct RGBImage: Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height * 3)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int) {
        self.init(width: width, height: height, pixels: [Float](repeating: 0, count: width * height * 3))
    }
}

/// Runs `body(rowStart, rowEnd)` over the image rows in parallel bands.
func parallelRows(_ height: Int, _ body: (Int, Int) -> Void) {
    let bands = max(1, min(height, ProcessInfo.processInfo.activeProcessorCount * 4))
    let per = (height + bands - 1) / bands
    DispatchQueue.concurrentPerform(iterations: bands) { b in
        let start = b * per
        let end = min(height, start + per)
        if start < end { body(start, end) }
    }
}
