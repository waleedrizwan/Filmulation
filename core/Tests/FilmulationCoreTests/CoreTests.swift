import XCTest
@testable import FilmulationCore

final class CoreTests: XCTestCase {
    func identity(_ n: Int) -> CubeLUT {
        var t: [Float] = []
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            t += [Float(r), Float(g), Float(b)].map { $0 / Float(n - 1) }
        } } }
        return CubeLUT(size: n, table: t)
    }

    /// A made-up warm, contrasty look, so the engine tests run without the generated film-look files.
    func syntheticLook() -> Look {
        let look = Look(id: "test-warm", name: "Test Warm", blurb: "")
        let n = 9
        var t: [Float] = []
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let x = Float(r) / Float(n - 1), y = Float(g) / Float(n - 1), z = Float(b) / Float(n - 1)
            t += [min(1, x * 1.1), 0.7 * y + 0.3 * y * y, 0.85 * z]
        } } }
        Looks.register(CubeLUT(size: n, table: t), stem: look.id)
        return look
    }

    /// Skips tests that check the real film looks: their files are generated locally and aren't in the repository.
    func requireInstalledLooks() throws {
        try XCTSkipIf(Looks.available(for: nil).count < Looks.all.count,
                      "film-look files not installed (see core/Sources/FilmulationCore/Resources/LUTs/README.md)")
    }

    func randomImage(_ w: Int, _ h: Int) -> RGBA8Image {
        RGBA8Image(width: w, height: h, bytes: (0..<(w * h * 4)).map { _ in UInt8.random(in: 0...255) })
    }

    // MARK: engine (no look files needed)

    func testIdentityLUTIsNoOp() {
        let px: [Float] = (0..<300).map { _ in Float.random(in: 0...1) }
        let img = RGBImage(width: 10, height: 10, pixels: px)
        let out = identity(17).apply(to: img)
        for (a, b) in zip(px, out.pixels) { XCTAssertEqual(a, b, accuracy: 1e-5) }
    }

    func testGrainFieldIsNormalisedAndFadesAtBlackAndWhite() {
        let field = GrainField(width: 64, height: 64, size: .small)
        XCTAssertEqual(standardDeviation(field.values), 1, accuracy: 0.01)
        var black = RGBImage(width: 64, height: 64)
        field.apply(to: &black, amount: .strong)
        XCTAssertEqual(black.pixels.map(abs).max()!, 0, accuracy: 1e-6)
    }

    func testGPUMatchesCPUOnSyntheticLook() throws {
        try assertGPUMatchesCPU(for: [syntheticLook()])
    }

    func testGPUStrengthZeroAndNoGrainIsIdentity() throws {
        let gpu = try XCTUnwrap(GPUEngine.shared)
        let src = randomImage(64, 48)
        let out = try gpu.render(try gpu.upload(src), settings: RenderSettings(look: syntheticLook(), strength: 0))
        for i in 0..<(64 * 48) { for ch in 0..<3 { XCTAssertEqual(out.bytes[i * 4 + ch], src.bytes[i * 4 + ch]) } }
    }

    func testTiledRenderMatchesOnePass() throws {
        let gpu = try XCTUnwrap(GPUEngine.shared)
        let src = randomImage(301, 197)   // tiles of 64 leave ragged edges on both sides
        var settings = RenderSettings(look: syntheticLook(), strength: 0.8, grain: .strong, grainSize: .large)
        settings.adjustments.exposure = 0.5
        settings.adjustments.color = 2
        let whole = try gpu.render(try gpu.upload(src), settings: settings)
        let tiled = try gpu.render(src, settings: settings, seed: 1, tileSize: 64, forceTiles: true)
        XCTAssertEqual(tiled.bytes, whole.bytes)
    }

    func testPhotosBiggerThanATextureRenderInsteadOfCrashing() throws {
        let gpu = try XCTUnwrap(GPUEngine.shared)
        let wide = randomImage(gpu.maxTextureSize + 616, 2)
        XCTAssertThrowsError(try gpu.upload(wide)) { XCTAssertTrue($0 is GPUEngineError) }
        let out = try gpu.render(wide, settings: RenderSettings(look: syntheticLook(), grain: .weak))
        XCTAssertEqual(out.width, wide.width)
        XCTAssertEqual(out.bytes.count, wide.bytes.count)
        XCTAssertTrue(stride(from: 3, to: out.bytes.count, by: 4).allSatisfy { out.bytes[$0] == 255 }, "every tile written")
    }

    func testStrengthZeroDoesNotNeedTheLookFile() throws {
        let missing = Look(id: "not-installed", name: "Missing", blurb: "")
        let settings = RenderSettings(look: missing, strength: 0)
        let gpu = try XCTUnwrap(GPUEngine.shared)
        let src = randomImage(16, 16)
        let rgb = { (img: RGBA8Image) in img.bytes.enumerated().filter { $0.offset % 4 != 3 }.map(\.element) }
        XCTAssertEqual(rgb(try gpu.render(try gpu.upload(src), settings: settings)), rgb(src))
        let base = PhotoIO.rgbImage(from: src)
        XCTAssertEqual(try Renderer.renderCPU(base, settings: settings).pixels, base.pixels)
        // At any other strength the missing file is an error, not a silent no-op
        XCTAssertThrowsError(try gpu.render(try gpu.upload(src), settings: RenderSettings(look: missing)))
    }

    func testDefaultSettingsRenderWhetherOrNotLooksAreInstalled() throws {
        let settings = RenderSettings()
        XCTAssertEqual(settings.look, Looks.available(for: nil).first)
        let gpu = try XCTUnwrap(GPUEngine.shared)
        XCTAssertNoThrow(try gpu.render(try gpu.upload(randomImage(16, 16)), settings: settings))
    }

    func testGPUGrainStrengthMatchesCPUGrain() throws {
        // On mid-grey the grain's standard deviation should be close to the CPU grain's (same settings)
        let gpu = try XCTUnwrap(GPUEngine.shared)
        let w = 1200, h = 900
        let grey = RGBA8Image(width: w, height: h, bytes: [UInt8](repeating: 128, count: w * h * 4))
        for amount in [GrainAmount.weak, .strong] {
            for size in GrainSize.allCases {
                let s = RenderSettings(look: nil, grain: amount, grainSize: size)
                let g = try gpu.render(try gpu.upload(grey), settings: s)
                let c = try Renderer.renderCPU(PhotoIO.rgbImage(from: grey), settings: s)
                let gv = stride(from: 0, to: g.bytes.count, by: 4).map { Float(g.bytes[$0]) / 255 }
                let cv = stride(from: 0, to: c.pixels.count, by: 3).map { c.pixels[$0] }
                let ratio = standardDeviation(gv) / standardDeviation(cv)
                XCTAssertEqual(ratio, 1, accuracy: 0.2, "\(amount) \(size)")
            }
        }
    }

    func testRecipeParsing() throws {
        let r = try XCTUnwrap(Recipes.parse([
            "name": "Test", "film": "Classic Chrome", "grain": "strong l", "ev": "-1/3", "color": -4, "wbr": 2,
            "wbb": "-3", "h-tone": 1, "s-tone": 2, "dr": "DR200", "ccfx": "weak", "ccfxb": "strong", "sensor": 4,
            "creator": "Me",
        ], id: 7))
        XCTAssertEqual(r.lookID, "classic-chrome")
        XCTAssertEqual(r.grain, .strong)
        XCTAssertEqual(r.grainSize, .large)
        XCTAssertEqual(r.adjustments.exposure, -1.0 / 3, accuracy: 1e-4)
        XCTAssertEqual(r.adjustments.color, -4)
        XCTAssertEqual(r.adjustments.wbRed, 2)
        XCTAssertEqual(r.adjustments.wbBlue, -3)
        XCTAssertEqual(r.adjustments.highlight, 0.25)   // +1, softened by DR200
        XCTAssertEqual(r.adjustments.chrome, 1)
        XCTAssertEqual(r.adjustments.chromeBlue, 2)
        XCTAssertNil(Recipes.parse(["film": "Classic Chrome"], id: 0), "a recipe needs a name")
    }

    func testStrengthZeroGivesOriginal() {
        let base = RGBImage(width: 1, height: 1, pixels: [0.2, 0.4, 0.6])
        let looked = RGBImage(width: 1, height: 1, pixels: [0.9, 0.9, 0.9])
        let out = Renderer.finish(base: base, looked: looked, settings: RenderSettings(strength: 0), grain: nil)
        XCTAssertEqual(out.pixels, base.pixels)
    }

    // MARK: the real film looks (skipped when their files aren't installed)

    func assertGPUMatchesCPU(for looks: [Look]) throws {
        let gpu = try XCTUnwrap(GPUEngine.shared)
        let src = randomImage(97, 61)
        for look in looks {
            let settings = RenderSettings(look: look, strength: 1)
            let g = try gpu.render(try gpu.upload(src), settings: settings)
            let c = try Renderer.renderCPU(PhotoIO.rgbImage(from: src), settings: settings)
            var worst = 0
            for i in 0..<(src.width * src.height) {
                for ch in 0..<3 {
                    let cpu = Int(min(max(c.pixels[i * 3 + ch], 0), 1) * 255 + 0.5)
                    worst = max(worst, abs(cpu - Int(g.bytes[i * 4 + ch])))
                }
            }
            XCTAssertLessThanOrEqual(worst, 1, look.id)
        }
    }

    func testGPUMatchesCPUOnInstalledLooks() throws {
        try requireInstalledLooks()
        try assertGPUMatchesCPU(for: Looks.all)
    }

    func testAllBundledLooksLoad() throws {
        try requireInstalledLooks()
        for look in Looks.all {
            let lut = try Looks.lut(for: look)
            XCTAssertEqual(lut.size, 33, look.id)
        }
    }

    func testProviaLeavesPhotoNearlyUnchanged() throws {
        try requireInstalledLooks()
        // provia_inv: Provia(Provia⁻¹(x)) ≈ x, so mid-tones should barely move
        let img = RGBImage(width: 3, height: 1, pixels: [0.5, 0.5, 0.5, 0.3, 0.5, 0.7, 0.8, 0.6, 0.4])
        let out = try Looks.lut(for: Looks.all[0]).apply(to: img)
        for (a, b) in zip(img.pixels, out.pixels) { XCTAssertEqual(a, b, accuracy: 0.02) }
    }

    func testAcrosIsMonochrome() throws {
        try requireInstalledLooks()
        let img = RGBImage(width: 1, height: 1, pixels: [0.8, 0.2, 0.3])
        let out = try Looks.lut(for: Looks.all.first { $0.id == "acros" }!).apply(to: img)
        XCTAssertEqual(out.pixels[0], out.pixels[1], accuracy: 0.01)
        XCTAssertEqual(out.pixels[1], out.pixels[2], accuracy: 0.01)
    }

    func testCameraProfilesFilterLooks() throws {
        try requireInstalledLooks()
        let xt2 = Cameras.camera("x-t2")!, x100vi = Cameras.camera("x100vi")!, xt5 = Cameras.camera("x-t5")!
        let ids = { (c: Camera) in Set(Looks.available(for: c).map(\.id)) }
        XCTAssertFalse(ids(xt2).contains("eterna"))               // X-T2 predates Eterna
        XCTAssertFalse(ids(xt5).contains("reala-ace"))            // X-T5 has no Reala Ace
        XCTAssertTrue(ids(xt5).contains("nostalgic-neg"))
        XCTAssertEqual(ids(x100vi).count, 20)                     // newest bodies have everything
        XCTAssertEqual(Looks.available(for: nil).count, Looks.all.count)
    }

    func testCamerasUseTheirOwnEterna() throws {
        try requireInstalledLooks()
        try XCTSkipIf(Looks.cameraLUTs.isEmpty, "per-camera look files not installed")
        let gpu = try XCTUnwrap(GPUEngine.shared)
        let img = try gpu.upload(randomImage(64, 64))
        let eterna = Looks.look("eterna")!
        let shared = try gpu.render(img, settings: RenderSettings(look: eterna))
        for id in ["x-t5", "x-h1", "gfx100II"] {
            let cam = Cameras.camera(id)!
            XCTAssertTrue(Cameras.hasOwnEterna(cam), id)
            XCTAssertNotEqual(Looks.lutFile(for: eterna, camera: cam), "eterna", id)
            let own = try gpu.render(img, settings: RenderSettings(look: eterna, camera: cam))
            XCTAssertNotEqual(own.bytes, shared.bytes, id)
        }
        // Looks Fujifilm only publishes once stay shared
        XCTAssertEqual(Looks.lutFile(for: Looks.look("velvia")!, camera: Cameras.camera("x-t5")), "velvia")
    }

    func testBundledRecipesParseAndApply() throws {
        try requireInstalledLooks()
        try XCTSkipIf(Recipes.all.isEmpty, "recipes.json not installed")
        XCTAssertEqual(Recipes.all.count, 204)
        XCTAssertTrue(Recipes.all.allSatisfy { $0.lookID != nil || $0.film.contains("+B") }, "unmapped film")
        let r = try XCTUnwrap(Recipes.all.first { $0.name == "Agfacolor Vintage" })
        XCTAssertEqual(r.lookID, "classic-chrome")
        XCTAssertEqual(r.grain, .strong)
        XCTAssertEqual(r.adjustments.exposure, -1.0 / 3, accuracy: 1e-4)
        XCTAssertEqual(r.adjustments.color, -4)
        XCTAssertEqual(Recipes.available(for: Cameras.camera("x-h1")).allSatisfy { $0.sensor == 3 }, true)

        let gpu = try XCTUnwrap(GPUEngine.shared)
        let img = try gpu.upload(randomImage(48, 48))
        let plain = try gpu.render(img, settings: RenderSettings(look: Looks.look("classic-chrome")))
        var s = r.apply(to: RenderSettings())
        s.grain = .off
        let withRecipe = try gpu.render(img, settings: s)
        XCTAssertNotEqual(plain.bytes, withRecipe.bytes)
    }

    func testMonochromeLooksAreGrey() throws {
        try requireInstalledLooks()
        let gpu = try XCTUnwrap(GPUEngine.shared)
        let img = try gpu.upload(randomImage(32, 32))
        for id in ["monochrome", "monochrome-r", "acros-ye", "acros-g"] {
            let out = try gpu.render(img, settings: RenderSettings(look: Looks.look(id)!))
            for i in stride(from: 0, to: out.bytes.count, by: 4) {
                XCTAssertLessThanOrEqual(abs(Int(out.bytes[i]) - Int(out.bytes[i + 2])), 2, id)
            }
        }
    }
}
