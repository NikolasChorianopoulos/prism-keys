# Releasing Prism Keys

Notes for the maintainer: how to publish a new version so installed copies update automatically.

## Day-to-day changes

1. Make changes, then build and install locally to try them:

   ```bash
   scripts/build-app.sh && rm -rf "/Applications/Prism Keys.app" && cp -R "dist/Prism Keys.app" /Applications/
   ```

   Local builds work, but don't receive updates; only released builds do.
2. Run the tests with `swift test`, then commit.
3. Release when you want users to get the changes (below).

## One-time setup

1. **Signing certificate.** Create a self-signed code-signing certificate (any name, set as `SIGN_IDENTITY` in `release.config`) and **back it up** (Keychain Access → My Certificates → Export). Every release must be signed with the same one, or users lose their permissions after updating.
2. Create the GitHub repo and set `GITHUB_REPO` in `release.config`.
3. Run `scripts/setup-updates.sh`. It creates the update-signing key: the private key goes in your Keychain and the public key in `release.config`. **Back up the private key** as the script explains. Without it you can't ship updates to existing installs.
4. Publish a first release, e.g. `scripts/release.sh 1.0.0`. Copies installed from it receive later updates.

## Each new version

```bash
scripts/release.sh 1.0.1 "What's new in this version"
```

This bumps `VERSION`, builds a universal DMG, signs it for Sparkle, writes `appcast.xml`, tags the release and (with the `gh` CLI) uploads both files to a GitHub release. Installed apps find it via `https://github.com/<repo>/releases/latest/download/appcast.xml`.

Version numbers: `1.0.x` for fixes, `1.x.0` for new features, `x.0.0` for big changes.

## Rules that keep updates working

- **Always release with `scripts/release.sh`.** It signs the update; installed apps reject anything unsigned.
- **Never lose the two keys:** the code-signing certificate (`SIGN_IDENTITY`) and the Sparkle update key. If either is lost, existing installs can't be updated, and users would have to download the next version by hand.
- **Never change the bundle ID** (`BUNDLE_ID` in `release.config`).
