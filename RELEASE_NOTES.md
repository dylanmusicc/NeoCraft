# NeoCraft 2.0.0

Native Minecraft: Java Edition launcher for macOS — Swift 6 + SwiftUI, tuned for Apple silicon and 8 GB Macs.

## Install

- **`NeoCraft-2.0.0.pkg`** — guided installer, places the app in `/Applications` (recommended)
- **`NeoCraft-2.0.0.dmg`** — classic drag-to-Applications disk image

> NeoCraft is ad-hoc signed and not notarized yet. On first launch, right-click the app → **Open** (or run `xattr -cr /Applications/NeoCraft.app`).

Requires macOS 14+ on Apple silicon. A Microsoft account that owns Minecraft: Java Edition is needed to play.

## Highlights

- **Microsoft sign-in** via device-code flow — tokens live in the Keychain
- **One-click Play**: Mojang version resolution, Fabric, automatic Eclipse Temurin JDK download, Neo Boost preset
- **Instances**: isolated game directories with per-instance loader, Java runtime, memory and JVM args
- **Mod Library**: Modrinth search with version/Fabric-aware filtering and dependency resolution
- **Bedrock Edition (beta)**: bundled NeoCraft Bedrock companion (Wine + D3DMetal)
- **Quiet performance profile**: 4.5 GB heap default, G1GC tuning, FPS cap and render-distance presets for fanless Macs
- Fully localized (en, en-GB, de, es, fr, ru)

## Notes

- First launch downloads the correct Temurin JDK into `~/Library/Application Support/NeoCraft/runtime`
- NeoCraft is an independent project, not affiliated with Mojang, Microsoft, Fabric or Modrinth

## Credits

- NeoCraft — design, code and packaging by the NeoCraft project
- Fonts — PressStart2P by CodeMan38, Silkscreen by Jason Kottke (free for any use)
- dmgbuild — dmgbuild/dmgbuild contributors (DMG packaging)
- Minecraft, Fabric, Modrinth and all in-game content belong to their respective owners

## Warnings & notices

- **Unofficial software** — community launcher, not affiliated with Mojang or Microsoft. Use at your own risk.
- **No warranty** — provided "as is"; see the in-installer license for full terms.
- **Account required** — you must own Minecraft: Java Edition and sign in with a Microsoft account.
- **Ad-hoc signed** — not notarized; macOS Gatekeeper will warn on first launch (right-click → Open).
- **Third-party downloads** — runtimes, libraries and mods are fetched at runtime from Mojang, Adoptium, Fabric and Modrinth under their own licenses.
- **Bedrock beta** — requires macOS 27 and a Microsoft account that owns Minecraft for Windows.
