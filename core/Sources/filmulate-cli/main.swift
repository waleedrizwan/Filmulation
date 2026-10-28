// Dev tool: render one photo with the engine and report timings.
//   filmulate-cli <in> <look-id> <out.jpg> [maxPixelSize] [weak|strong] [small|large] [--cpu]
//                 [--camera <id>] [--recipe "<recipe name>"]   (a recipe overrides look and grain)
import CoreGraphics
import FilmulationCore
import Foundation

var args = CommandLine.arguments
let useCPU = args.contains("--cpu")
args.removeAll { $0 == "--cpu" }
func option(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
let cameraID = option("--camera"), recipeName = option("--recipe")
guard args.count >= 4, let look = Looks.all.first(where: { $0.id == args[2] }) else {
    print("usage: filmulate-cli <in> <look-id> <out.jpg> [maxPixelSize] [weak|strong] [small|large] [--cpu]")
    print("looks:", Looks.all.map(\.id).joined(separator: ", "))
    exit(1)
}
let source = PhotoSource.url(URL(fileURLWithPath: args[1]))
let maxSize = args.count > 4 ? Int(args[4]) : nil
var settings = RenderSettings(look: look)
if args.count > 5 { settings.grain = GrainAmount.allCases.first { $0.rawValue.lowercased() == args[5] } ?? .off }
if args.count > 6 { settings.grainSize = GrainSize.allCases.first { $0.rawValue.lowercased() == args[6] } ?? .small }
if let cameraID {
    guard let cam = Cameras.camera(cameraID) else { print("unknown camera \(cameraID)"); exit(1) }
    settings.camera = cam
}
if let recipeName {
    guard let r = Recipes.all.first(where: { $0.name == recipeName }) else { print("unknown recipe"); exit(1) }
    settings = r.apply(to: settings)
    print("recipe:", r.summary)
}

func ms(_ a: Date, _ b: Date) -> String { String(format: "%.1f ms", b.timeIntervalSince(a) * 1000) }

let t0 = Date()
let pixels = try PhotoIO.loadRGBA8(source, maxPixelSize: maxSize)
let t1 = Date()
let cg: CGImage
var detail = ""
if useCPU || GPUEngine.shared == nil {
    cg = PhotoIO.cgImage(from: try Renderer.renderCPU(PhotoIO.rgbImage(from: pixels), settings: settings))
    detail = "CPU"
} else if max(pixels.width, pixels.height) > GPUEngine.shared!.maxTextureSize {
    cg = PhotoIO.cgImage(from: try GPUEngine.shared!.render(pixels, settings: settings))
    detail = "GPU, in tiles"
} else {
    let gpu = GPUEngine.shared!
    gpu.preloadLooks()
    let up0 = Date()
    let img = try gpu.upload(pixels)
    let r0 = Date()
    _ = try gpu.render(img, settings: settings)            // warm-up
    let r1 = Date()
    let out = try gpu.render(img, settings: settings)
    let r2 = Date()
    cg = PhotoIO.cgImage(from: out)
    detail = "GPU  upload \(ms(up0, r0))  first render \(ms(r0, r1))  render \(ms(r1, r2))"
}
let t2 = Date()
try PhotoIO.writeJPEG(cg, to: URL(fileURLWithPath: args[3]), metadataFrom: source)
let t3 = Date()
print("\(pixels.width)x\(pixels.height)  decode \(ms(t0, t1))  process \(ms(t1, t2)) [\(detail)]  encode \(ms(t2, t3))")
