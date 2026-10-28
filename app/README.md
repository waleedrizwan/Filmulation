# Filmulation (Mac app)

Applies film looks to any photo. No look files are included yet.

```bash
./build_app.sh                      # builds build/Filmulation.app (release, ad-hoc signed)
open build/Filmulation.app          # or drop photos/folders onto the app icon
swift test --package-path ../core   # engine unit tests
swift run --package-path ../core -c release filmulate-cli in.jpg classic-chrome out.jpg [maxPx] [weak|strong] [small|large]
```

## Using it

- **Add photos:** drag photos or a folder into the window or onto the Dock icon, or use ⌘O. HEIC, JPEG, PNG, TIFF and WebP are supported. iPhone rotation and Display P3 colour are handled.
- **Recipe:** browse community recipes. Picking one sets the look, grain, tone, colour, Color Chrome, white-balance shift and exposure.
- **Look:** pick a film simulation. Each row previews the current photo and says what the look does.
- **Strength:** mixes the look with the original, from 0 to 100%.
- **Grain:** Off / Weak / Strong, Small / Large. It is monochrome and fades in shadows and highlights.
- **Before / After:** use the button under the photo, or press Space. Changing any setting jumps back to After.
- **Export:** ⌘E exports the current photo and ⇧⌘E exports all. Exports are full-resolution JPEGs (sRGB, quality 93) named `<photo>_<look>.jpg`, with EXIF and date kept. Your settings apply to every photo you export.

## Layout

- `../core/Sources/FilmulationCore`: the shared engine (GPU path in `GPUEngine.swift`).
  - `CubeLUT`: tetrahedral 3D LUT, CPU, multithreaded.
  - `Grain`: three-octave blurred noise, after darktable.
  - `ImageIO`: ImageIO/CoreGraphics load with colour management, and JPEG export.
  - `Renderer`, `Looks`.
- `Sources/Filmulation`: the SwiftUI app.
  - `PhotoStore`: state plus rendering. The 2000 px preview stays on the GPU, so every change is one Metal pass of about 4 ms.
- `../core/Sources/FilmulationCore/Resources/LUTs`: where look files go (none included).

Speed on Apple Silicon: about 4 ms per preview re-render and about 15 ms of GPU work for a full 12 MP photo; decode and encode take longer. GPU output matches the CPU reference within 1/255.
