#!/bin/bash
# Packages dist/Prism Keys.app into a drag-to-Applications DMG. Usage: scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
APP="dist/Prism Keys.app"
DMG="dist/PrismKeys-$VERSION.dmg"
[ -d "$APP" ] || scripts/build-app.sh

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Prism Keys" -srcfolder "$STAGE" -ov -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
rm -rf "$STAGE"
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
