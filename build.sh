#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
app="${BARK_APP_OUTPUT:-$PWD/dist/Bark Flow.app}"
# Build outside iCloud-managed source folders, whose materialization can change
# timestamps while the compiler reads a file.
stage="$(mktemp -d "${TMPDIR:-/tmp}/barkflow-source.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
cp Package.swift "$stage/"
cp -R Sources Tests "$stage/"
swift build --package-path "$stage" --build-system native -c release -debug-info-format none --jobs 2 --product BarkFlow
bin="$(swift build --package-path "$stage" --build-system native -c release --show-bin-path)"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/BarkFlow" "$app/Contents/MacOS/BarkFlow"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/ModelManifest.json "$app/Contents/Resources/ModelManifest.json"
cp Resources/StandardModelManifest.json "$app/Contents/Resources/StandardModelManifest.json"
cp Resources/PlusModelManifest.json "$app/Contents/Resources/PlusModelManifest.json"
cp Resources/THIRD-PARTY-NOTICES.txt "$app/Contents/Resources/THIRD-PARTY-NOTICES.txt"
for resource in "$bin"/*.bundle(N); do
    [[ -d "$resource" ]] && cp -R "$resource" "$app/Contents/Resources/"
done
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi
if [[ ! -f "$app/Contents/Resources/PlusModels/decoder-data/weights.json" ]]; then
    python3 -c 'import numpy' || { print 'Install NumPy in your build Python environment before preparing Plus.'; exit 1; }
    python3 download-models.py "$app/Contents/Resources/PlusModels" --model plus
    python3 prepare-plus.py "$app/Contents/Resources/PlusModels"
fi
xattr -cr "$app"
codesign --force --sign - --identifier local.barkflow.mac "$app"
print "Built: $app"
