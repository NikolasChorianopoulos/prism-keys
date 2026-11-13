#!/bin/bash
# One-time setup for Sparkle auto-updates:
#  1. downloads Sparkle's command line tools (sign_update, generate_keys) into .build/sparkle-tools
#  2. creates your update-signing key (private key stored in your login Keychain)
#  3. writes the public key into release.config
set -euo pipefail
cd "$(dirname "$0")/.."
VER=$(python3 -c 'import json;print([p["state"]["version"] for p in json.load(open("Package.resolved"))["pins"] if p["identity"]=="sparkle"][0])')
TOOLS=.build/sparkle-tools
if [ ! -x "$TOOLS/bin/sign_update" ]; then
  echo "▸ Downloading Sparkle $VER tools from github.com/sparkle-project"
  mkdir -p "$TOOLS"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$VER/Sparkle-$VER.tar.xz" | tar -xJ -C "$TOOLS"
fi
KEY=$("$TOOLS/bin/generate_keys" 2>/dev/null | grep -oE '[A-Za-z0-9+/=]{40,}' | tail -1 || true)
[ -z "$KEY" ] && KEY=$("$TOOLS/bin/generate_keys" -p)
sed -i '' "s|^SPARKLE_PUBLIC_KEY=.*|SPARKLE_PUBLIC_KEY=\"$KEY\"|" release.config
echo "✓ Public key saved to release.config: $KEY"
echo "  Back up the private key with: $TOOLS/bin/generate_keys -x sparkle-private-key.txt  (keep it secret!)"
