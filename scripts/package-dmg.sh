#!/bin/zsh
# Package an existing universal app with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-build/Flocon.app}"
image="${2:-build/Flocon.dmg}"
[[ -d "$app/Contents/MacOS" ]] || { print -u2 "App bundle not found: $app"; exit 1; }
mkdir -p "${image:h}"
staging="$(mktemp -d "${TMPDIR:-/tmp}/flocon-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Flocon.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Flocon -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$image"
if [[ -n "${IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$image"
fi
hdiutil verify "$image"
print "Built $image"
