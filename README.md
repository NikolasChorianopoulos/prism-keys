# Prism Keys

A menu bar app that brings lighting, key remapping, macros and notification alerts back to the **Razer BlackWidow Chroma** on modern macOS (Apple Silicon and Intel). It's for anyone whose keyboard is no longer supported by Razer Synapse.

> Prism Keys is an independent project. It is not affiliated with or endorsed by Razer Inc. Razer, BlackWidow and Chroma are trademarks of Razer Inc.

## Features

- **Menu bar dropdown:** on/off, profile, brightness, effects, color, speed, alert toggles.
- **Effects that run on the keyboard itself:** Static, Breathing, Spectrum, Wave, Reactive.
- **Effects animated by the app:** Rainbow, Ripple, Starlight, Heatmap, Gradient.
- **Per-key colors:** click keys on an on-screen keyboard to paint them.
- **Remapping:** remap any key on the Razer keyboard only. Your Mac's built-in keyboard isn't affected.
- **Macros:** type text, press shortcuts, wait, open apps or URLs, run shell commands. Attach them to any key, including M1–M5.
- **M1–M5 keys:** turn on "Enable M1–M5 keys". The keyboard switches to driver mode, and Prism Keys handles the Fn shortcuts itself: F1–F3 volume, F5–F7 media, F10 Gaming mode (Win/⌘ key off, with its indicator light), F11/F12 brightness, Pause sleep. Quitting the app hands them back to the keyboard.
- **Notification and call alerts:** a sweep across the F-keys for notifications, and a pulse over the whole keyboard for incoming calls (FaceTime/iPhone, or any app whose notification says "incoming call"). A reminder can stay lit until you press a key.
- **Profiles:** export them and import them on another Mac.
- **Automatic updates** via Sparkle.
- **Other:** lights turn off when the display sleeps, and settings are reapplied after unplugging or waking.

Supported: BlackWidow Chroma (`1532:0203`), plus the Tournament Edition and Overwatch variants (untested).

## Install

1. Download `PrismKeys-x.y.z.dmg` from [Releases](../../releases), open it, and drag **Prism Keys** into **Applications**.
2. On first launch, **right-click the app → Open**, then confirm. This build isn't notarized by Apple, so macOS asks once.
3. Optional permissions, in **System Settings → Privacy & Security**:

| Permission | Needed for |
|---|---|
| Accessibility | Macros, notification and call alerts (read from on-screen banners), typing effects |
| Input Monitoring | M1–M5 keys, and the Fn shortcuts while they're enabled |
| Full Disk Access | Optional: a second way to catch notifications |

Basic lighting needs no permissions.

### Troubleshooting

- **The keyboard flickers on bright colors, especially white.** It isn't getting enough power, which is common behind USB hubs. Plug it straight into the Mac, use a powered hub, or lower Settings → General → Maximum brightness.
- **A permission is on in System Settings but Prism Keys says it's missing.** That entry belongs to an older build. Run `tccutil reset All app.prismkeys.PrismKeys`, reopen Prism Keys and grant again.

### Using it from Shortcuts or scripts

```bash
open prismkeys://alert/notify     # or alert/call, alert/clear
open prismkeys://effect/wave      # any effect name
open prismkeys://profile/Gaming   # switch profile
open prismkeys://lights/off       # lights/on
```

## Build from source

You need macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't required.

```bash
scripts/build-app.sh      # → dist/Prism Keys.app
scripts/make-dmg.sh       # → dist/PrismKeys-<version>.dmg
```

## Publishing updates

One-time setup:

0. Signing: builds are signed with the identity in `release.config` (`SIGN_IDENTITY`). A self-signed certificate is fine. Sign every release with the same one so macOS keeps users' permissions after updates, and back it up from Keychain Access.

1. Create the GitHub repo and set `GITHUB_REPO` in `release.config`.
2. Run `scripts/setup-updates.sh`. It creates the update-signing key: the private key goes in your Keychain and the public key in `release.config`. Back up the private key as the script explains. Without it you can't ship updates to existing installs.
3. Build and publish a first release, e.g. `scripts/release.sh 1.0.0`. Copies installed from it will receive updates.

For each new version:

```bash
scripts/release.sh 1.1.0 "What's new in this version"
```

This bumps `VERSION`, builds a universal DMG, signs it for Sparkle, writes `appcast.xml`, tags the release and (with the `gh` CLI) uploads both files to a GitHub release. Installed apps find it via `https://github.com/<repo>/releases/latest/download/appcast.xml`.

## How it works

Lighting commands are sent to the keyboard as USB HID feature reports, using the protocol documented by the open-source [OpenRazer](https://openrazer.github.io) project. Remaps use macOS's built-in `hidutil`, limited to this one keyboard. Macros fire through a keyboard event tap.
