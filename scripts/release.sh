#!/bin/bash
# Builds a release and publishes it so installed copies auto-update.
# Usage: scripts/release.sh [--yes] 1.0.1 ["What's new text"]   (--yes publishes without asking)
set -euo pipefail
cd "$(dirname "$0")/.."
source release.config
YES=0
[ "${1:-}" = "--yes" ] && { YES=1; shift; }
NEW="${1:?Usage: scripts/release.sh [--yes] <version> [notes]}"
NOTES="${2:-Bug fixes and improvements.}"
[ -n "$GITHUB_REPO" ] || { echo "Set GITHUB_REPO in release.config first."; exit 1; }
[ -n "$SPARKLE_PUBLIC_KEY" ] || { echo "Run scripts/setup-updates.sh first."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }

echo "$NEW" > VERSION
git diff --quiet VERSION || git commit -qm "Release $NEW" VERSION
scripts/build-app.sh
scripts/make-dmg.sh
DMG="dist/PrismKeys-$NEW.dmg"
# Fixed-name copy: the README's download button links to releases/latest/download/PrismKeys.dmg
cp "$DMG" dist/PrismKeys.dmg
BUILD=$(git rev-list --count HEAD)

SIG=$(.build/sparkle-tools/bin/sign_update "$DMG")   # → sparkle:edSignature="…" length="…"
URL="https://github.com/$GITHUB_REPO/releases/download/v$NEW/PrismKeys-$NEW.dmg"
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Prism Keys</title>
    <item>
      <title>Version $NEW</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$NEW</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>$NOTES</p>]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIG />
    </item>
  </channel>
</rss>
XML
git tag "v$NEW"
echo "✓ Built $DMG and dist/appcast.xml"
if command -v gh >/dev/null; then
  ok=n
  if [ "$YES" = 1 ]; then ok=y; else read -r -p "Publish v$NEW to GitHub now (push tag + create release)? [y/N] " ok; fi
  if [ "$ok" = "y" ]; then
    git push -u origin HEAD && git push origin "v$NEW"
    gh release create "v$NEW" "$DMG" dist/PrismKeys.dmg dist/appcast.xml --repo "$GITHUB_REPO" --title "Prism Keys $NEW" --notes "$NOTES"
    echo "✓ Released. Installed copies will see the update within a day (or via Check for Updates)."
  fi
else
  echo "Upload $DMG, dist/PrismKeys.dmg and dist/appcast.xml to a GitHub release named v$NEW."
fi
