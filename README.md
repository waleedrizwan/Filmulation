# Filmulation

Film looks for any photo: on the Mac and the iPhone, fully on-device, GPU-fast.

> **Status:** no film looks are included right now. The engine, apps, grain, strength, before/after and batch export all work. They're waiting on a set of openly licensed film looks that can be shared freely. Until then the only look is **Original**: grain and export still work, and the look list fills in once look files are installed (see [`core/Sources/FilmulationCore/Resources/LUTs/README.md`](core/Sources/FilmulationCore/Resources/LUTs/README.md)).

## Build

**Mac app**

```bash
cd app && ./build_app.sh && open build/Filmulation.app
```

**iPhone app** (needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen))

```bash
cd ios && xcodegen generate && open FilmulationiOS.xcodeproj
```

In Xcode, set your own Team and bundle identifier under *Signing & Capabilities*, pick your iPhone and press Run.

**Engine tests**

```bash
swift test --package-path core
```

Engine tests use a made-up look, so they run anywhere. Tests that check the real film looks are skipped when no look files are installed.

## Layout

| Folder | What it is |
|---|---|
| `core/` | Swift package `FilmulationCore`. It contains: <ul><li>a Metal GPU pipeline that applies the 3D LUT, strength and grain in one pass</li><li>a CPU reference path</li><li>colour-managed image I/O</li><li>tests</li><li>the `filmulate-cli` dev tool</li></ul> |
| `app/` | Mac app (SwiftUI) with drag and drop, looks, strength, grain, Before/After and batch export. |
| `ios/` | iPhone app (SwiftUI) that picks from Photos, previews live and saves to the camera roll. |

## Speed (12 MP photo, Apple Silicon)

| Step | Time |
|---|---|
| Decode HEIC to sRGB | ~200 ms |
| GPU look + grain | ~12–16 ms |
| JPEG encode | ~50 ms |
| Live preview re-render at 2048 px | ~4 ms |

## License

The code is under the MIT License (see [`LICENSE`](LICENSE)).
