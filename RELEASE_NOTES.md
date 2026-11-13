# NeoCraft 2.0.1

Native Minecraft: Java Edition launcher for macOS — Swift 6 + SwiftUI, tuned for Apple silicon and 8 GB Macs.

## Install

- **`NeoCraft-2.0.1.pkg`** — guided installer, places the app in `/Applications` (recommended)
- **`NeoCraft-2.0.1.dmg`** — classic drag-to-Applications disk image

> NeoCraft is ad-hoc signed and not notarized yet. On first launch, right-click the app → **Open** (or run `xattr -cr /Applications/NeoCraft.app`).

Requires macOS 14+ on Apple silicon. A Microsoft account that owns Minecraft: Java Edition is needed to play.

## What's new in 2.0.1 — Server Hosting & Dashboard

- **Host a world as a dedicated server** — pick any single-player world in a Java instance's Worlds tab and press **Host**. NeoCraft downloads the official Mojang `server.jar` for the matching version (SHA-1 verified), copies the save into its own server folder and writes `eula.txt` + `server.properties`.
- **Server Dashboard (new sidebar page)** — every hosted server gets a full management console:
  - **Live server console** with command input (`say`, `list`, `op`, `kick`, `save-all`, …) streamed in real time
  - **Player list** parsed from join/leave events plus live ping counts, with one-click **Op**/**Kick**
  - **Lifecycle**: Start, Stop (`stop` command → clean world save, SIGTERM/SIGKILL escalation), Restart
  - **Server Settings** editor for `server.properties`: MOTD, port, online-mode, PvP, whitelist, allow-flight, spawn protection, difficulty, gamemode, player/view/simulation distances — unknown keys are preserved
  - **Server Files** browser: navigate the server folder, preview text files (`ops.json`, `whitelist.json`, `banned-*.json`, logs, …), reveal in Finder, delete loose files
  - **World Backups**: snapshot the hosted world into `backups/`, restore or delete snapshots (server must be stopped)
  - **Sync World from Instance** re-copies the single-player save over the hosted world
  - **Start with NeoCraft** per-server auto-start on launch
- **Sidebar integration** — hosted servers appear as a quick-jump group under the nav with live status dots, plus a count badge on the Dashboard entry.
- **Servers tab** — the Hosted Worlds card now links straight into the Dashboard.

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
- Hosted servers are **Java Edition only** and run as vanilla — client-side Fabric mods are not carried over to the server
- macOS may ask once whether NeoCraft may accept incoming network connections — required for LAN friends to join
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
