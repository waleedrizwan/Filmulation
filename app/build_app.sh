#!/bin/zsh
# Builds Filmulation.app (release) into app/build/ and ad-hoc signs it so it runs locally.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product Filmulation
BIN=$(swift build -c release --show-bin-path)
APP=build/Filmulation.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Filmulation" "$APP/Contents/MacOS/Filmulation"
cp -R ../core/Sources/FilmulationCore/Resources/LUTs "$APP/Contents/Resources/LUTs"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Filmulation</string>
    <key>CFBundleDisplayName</key><string>Filmulation</string>
    <key>CFBundleIdentifier</key><string>local.filmulation.app</string>
    <key>CFBundleExecutable</key><string>Filmulation</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Image</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>public.image</string><string>public.folder</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
