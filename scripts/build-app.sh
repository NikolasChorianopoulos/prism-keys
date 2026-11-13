#!/bin/bash
# Builds "dist/Prism Keys.app" (universal when possible). Usage: scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source release.config

VERSION=$(cat VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
APP="dist/Prism Keys.app"
FEED=""
[ -n "$GITHUB_REPO" ] && FEED="https://github.com/$GITHUB_REPO/releases/latest/download/appcast.xml"

echo "▸ Building Prism Keys $VERSION ($BUILD)"
TMPBIN=$(mktemp -d)
swift build -c release --arch arm64 2>&1 | grep -vE "search path .* not found" | tail -2
BINDIR=$(swift build -c release --arch arm64 --show-bin-path)
cp "$BINDIR/PrismKeys" "$TMPBIN/PrismKeys-arm64"
cp -R "$BINDIR/Sparkle.framework" "$TMPBIN/"
BINARIES=("$TMPBIN/PrismKeys-arm64")
if swift build -c release --arch x86_64 >"$TMPBIN/x86.log" 2>&1; then
  cp "$(swift build -c release --arch x86_64 --show-bin-path)/PrismKeys" "$TMPBIN/PrismKeys-x86_64"
  BINARIES+=("$TMPBIN/PrismKeys-x86_64")
  echo "▸ Universal binary (Apple Silicon + Intel)"
else
  echo "▸ Apple Silicon only (Intel build failed: $TMPBIN/x86.log)"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/PrismKeys"

# Sparkle framework
cp -R "$TMPBIN/Sparkle.framework" "$APP/Contents/Frameworks/"

# Info.plist
sed -e "s|__VERSION__|$VERSION|" -e "s|__BUILD__|$BUILD|" -e "s|__BUNDLE_ID__|$BUNDLE_ID|" \
    -e "s|__FEED_URL__|$FEED|" -e "s|__PUBLIC_KEY__|$SPARKLE_PUBLIC_KEY|" packaging/Info.plist > "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"

# Icon
if [ ! -f packaging/AppIcon.icns ]; then
  [ -f packaging/AppIcon-1024.png ] || swift scripts/make-icon.swift packaging/AppIcon-1024.png
  ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s packaging/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) packaging/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o packaging/AppIcon.icns
fi
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Code signing: SIGN_IDENTITY from release.config (falls back to ad-hoc if it isn't in the Keychain)
IDENTITY="${SIGN_IDENTITY:--}"
if [ "$IDENTITY" != "-" ] && ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  echo "▸ Signing identity '$IDENTITY' not found; using ad-hoc (permissions won't survive updates)"
  IDENTITY="-"
fi
OPTS=(--force --timestamp=none --sign "$IDENTITY")
[[ "$IDENTITY" == "Developer ID"* ]] && OPTS=(--force --timestamp --options runtime --sign "$IDENTITY")
FW="$APP/Contents/Frameworks/Sparkle.framework"
for item in "$FW/Versions/B/XPCServices/Installer.xpc" "$FW/Versions/B/XPCServices/Downloader.xpc" \
            "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app" "$FW"; do
  [ -e "$item" ] && codesign "${OPTS[@]}" "$item"
done
codesign "${OPTS[@]}" "$APP"
codesign --verify --deep --strict "$APP" 2>/dev/null || [ "$IDENTITY" != "-" ] || { echo "signature check failed"; exit 1; }
echo "▸ Signed ($IDENTITY)"
echo "✓ $APP"
