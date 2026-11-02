#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
app="${BARK_APP_OUTPUT:-$PWD/dist/Bark Flow.app}"
dmg="${BARK_DMG_OUTPUT:-$PWD/dist/Bark Flow.dmg}"
[[ -d "$app" ]] || { print 'Build the app first with ./build.sh'; exit 1; }
[[ ! -d "$app/Contents/Resources/Models" ]] || { print 'This image must contain Plus only. Remove the Pro model from the build and re-sign first.'; exit 1; }
stage="$(mktemp -d "${TMPDIR:-/tmp}/barkflow-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$(dirname "$dmg")"
ditto "$app" "$stage/Bark Flow.app"
ln -s /Applications "$stage/Applications"
cp INSTALL.txt "$stage/Read Me First.txt"
codesign --verify --deep --strict "$stage/Bark Flow.app"
hdiutil create -srcfolder "$stage" -fs HFS+ -format UDZO -volname 'Bark Flow' -ov "$dmg"
hdiutil verify "$dmg"
print "Created: $dmg"
