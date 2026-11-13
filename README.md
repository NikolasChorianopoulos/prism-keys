# Prism Keys

A menu bar app that brings lighting, macros, key remapping and notification alerts back to the **Razer BlackWidow Chroma** on modern macOS. It's for anyone whose keyboard is no longer supported by Razer Synapse.

> Prism Keys is an independent project. It is not affiliated with or endorsed by Razer Inc. Razer, BlackWidow and Chroma are trademarks of Razer Inc.

## Supported keyboards

| Keyboard | Status |
|---|---|
| Razer BlackWidow Chroma (`1532:0203`) | Supported and tested (US layout, macOS 27, Apple Silicon) |
| BlackWidow Chroma Tournament Edition (`1532:0209`), BlackWidow Chroma Overwatch (`1532:0211`) | Should work, untested |
| Other first-generation Chroma keyboards (BlackWidow Chroma V2, BlackWidow X Chroma, Ornata Chroma) | Same protocol family; not enabled yet |
| Newer Razer keyboards (BlackWidow V3/V4, Huntsman, Cynosa…) | Not supported yet: they use a newer protocol |

If you plug in a Razer keyboard that isn't supported, Prism Keys says so and offers a link to request support. Reports from owners of the untested models are very welcome. The DMG also runs on Intel Macs, but that hasn't been tested yet.

## Features

**Lighting**
- Effects the keyboard runs itself: Static, Breathing, Spectrum, Wave, Reactive.
- Effects animated by the app: Rainbow, Ripple, Starlight, Heatmap, Gradient.
- Per-key colors: click keys on an on-screen keyboard to paint them.
- Brightness, profiles, and lights that turn off while the display sleeps.

**Keys and macros**
- **Macros:** type text, press shortcuts, wait, open apps or URLs, run shell commands. Attach them to M1–M5 or any other key.
- **On-the-fly recording:** press Fn+F9, type, press Fn+F9 again, then press the key that should play it back.
- **Remapping** for the Razer only. Your Mac's own keyboard isn't affected.
- **Fn shortcuts** as printed on the keys: volume, media, keyboard brightness, Gaming mode (Win/⌘ key off), sleep. The Gaming mode and macro indicator lights work too.
- **Windows-style keys:** Num Lock switches the numpad between numbers and arrows, Caps Lock is shared with your Mac's keyboard, and Home/End/Page Up/Page Down move the cursor in text fields.

**Alerts**
- A light sweep across the F-keys for notifications, and a pulse over the whole keyboard for incoming calls (iPhone calls via Continuity and FaceTime, tested with a real call; or any app whose notification says "incoming call").
- A reminder, in a color you choose, can stay lit until you press a key. A call alert stops when the call banner goes away.
- While an alert plays, the rest of the keyboard dims so it stands out. How much is adjustable, from not at all to fully off.
- A warning appears if an alert or reminder color is the same as your lighting color.

**Also**
- Export profiles and import them on another Mac.
- Automatic updates.
- Settings are reapplied after unplugging, waking or restarting.

## Install

1. Download `PrismKeys-x.y.z.dmg` from [Releases](../../releases), open it, and drag **Prism Keys** into **Applications**.
2. Open Prism Keys. Because the app isn't notarized by Apple, macOS blocks it the first time:
   - **macOS 15 or later:** click **Done**, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Prism Keys, and confirm.
   - **macOS 14:** right-click the app → **Open**, then confirm.
3. Prism Keys appears in the menu bar, and Settings opens on first launch.

### Permissions

All of these are optional and are granted in **System Settings → Privacy & Security**. Basic lighting needs none of them.

| Permission | Needed for |
|---|---|
| Accessibility | Macros, notification and call alerts (read from on-screen banners), typing effects, the Windows-style keys |
| Input Monitoring | M1–M5 and the Fn shortcuts, and the Num/Caps Lock lights |
| Full Disk Access | Optional: a second way to catch notifications |

Settings → General shows which permissions are granted and has buttons to grant the rest.

### M1–M5 and the Fn shortcuts

Turn on **M1–M5 macro keys** in the menu (or in Settings → Keys & Macros). The keyboard then switches to "driver mode": it sends M1–M5 and Fn to Prism Keys, and Prism Keys handles these Fn shortcuts itself:

| Fn + | Does |
|---|---|
| F1 / F2 / F3 | Mute / volume down / volume up |
| F5 / F6 / F7 | Previous / play-pause / next |
| F9 | Record a macro |
| F10 | Gaming mode (Win/⌘ key off) |
| F11 / F12 | Keyboard brightness down / up |
| Pause | Sleep |

Quitting Prism Keys switches the keyboard back to normal mode, and the keyboard handles Fn itself again.

## Troubleshooting

- **The keyboard flickers on bright colors, especially white.** It isn't getting enough power, which is common behind USB hubs. Plug it straight into the Mac, use a powered hub, or lower Settings → General → Maximum brightness.
- **A permission is on in System Settings but Prism Keys says it's missing.** That entry belongs to an older build. Run `tccutil reset All app.prismkeys.PrismKeys`, reopen Prism Keys and grant again.
- **The Fn keys or remaps behave oddly after Prism Keys crashed.** A crash can leave the keyboard in driver mode with Prism Keys' key changes still active. Reopen Prism Keys, or unplug the keyboard and plug it back in.
- **Scroll Lock / Pause change the screen brightness.** That's macOS: it treats those keys as F14/F15. Remap them in Keys & Macros if you prefer.
- **A key only works sometimes.** On older keyboards, worn switches can register only some presses. Compressed air or switch contact cleaner often helps.
- **Something else.** Settings → General → Open log shows what Prism Keys is doing. The log never contains your notifications' text or your macros' contents.

## Using it from Shortcuts or scripts

```bash
open prismkeys://alert/notify     # or alert/call, alert/clear
open prismkeys://effect/wave      # any effect name
open prismkeys://profile/Gaming   # switch profile
open prismkeys://lights/off       # or lights/on
open prismkeys://gamemode/on      # or gamemode/off (with M1–M5 enabled)
```

## Build from source

You need macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't required.

```bash
scripts/build-app.sh      # → dist/Prism Keys.app
scripts/make-dmg.sh       # → dist/PrismKeys-<version>.dmg
```

Builds are signed with the identity named in `release.config` (`SIGN_IDENTITY`). If that certificate isn't in your Keychain, the build falls back to ad-hoc signing. The app still runs, but macOS forgets its permissions after every rebuild.

Maintainers: see [RELEASING.md](RELEASING.md) for publishing new versions.

## How it works

- **Lighting:** commands are sent as USB HID feature reports, following the protocol documented by the open-source [OpenRazer](https://openrazer.github.io) project.
- **Remaps and Num Lock:** macOS's built-in `hidutil`, limited to this one keyboard.
- **Macros, alerts and the Windows-style keys:** a keyboard event tap and the Accessibility API. Each key event says which keyboard sent it, so changes apply to the Razer only.
- **M1–M5 and Fn:** in driver mode they arrive as a vendor-specific HID report, which Prism Keys reads directly.

## License

[MIT](LICENSE)
