#!/bin/zsh
# Universal Intel + Apple Silicon app. No downloads or third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p build
for architecture in arm64 x86_64; do
    flags=(--disable-sandbox --build-system native -c release --arch "$architecture")
    swift build "${flags[@]}"
    products="$(swift build "${flags[@]}" --show-bin-path)"
    cp "$products/Flocon" "build/Flocon-$architecture"
done
app=build/Flocon.app
# Replace only our generated bundle; never touch an installed application.
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create build/Flocon-arm64 build/Flocon-x86_64 -output "$app/Contents/MacOS/Flocon"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
cp Sources/Flocon/Rendering/Shaders.metal "$app/Contents/Resources/"
if [[ -n "${IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
lipo -archs "$app/Contents/MacOS/Flocon"
ditto -c -k --sequesterRsrc --keepParent "$app" build/Flocon.zip
./scripts/package-dmg.sh "$app" build/Flocon.dmg
print "Built $app, build/Flocon.zip and build/Flocon.dmg"
