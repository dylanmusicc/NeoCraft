# NeoCraft 2.1.3

Native Minecraft launcher for macOS — Java **and** Bedrock Edition, Swift 6 + SwiftUI, tuned for Apple silicon and 8 GB Macs.

## Install

- **`NeoCraft-2.1.3.pkg`** — guided installer, places the app in `/Applications` (recommended)
- **`NeoCraft-2.1.3.dmg`** — classic drag-to-Applications disk image

> NeoCraft is ad-hoc signed and not notarized yet. On first launch, right-click the app → **Open** (or run `xattr -cr /Applications/NeoCraft.app`).

Requires macOS 14+ on Apple silicon. A Microsoft account that owns Minecraft is needed to play.

## What's new in 2.1.3 — Bedrock Performance Mode

- **Performance mode for Bedrock (on by default)** — every launch now writes a tuned set of graphics options for the MacBook Neo's A18 Pro and its 8 GB of memory: Fancy instead of Vibrant Visuals, no MSAA (which also works around the Metal 4 interface bug), 16 chunks of render distance, cheapest fog/reflections/shadows/bloom and a 60 fps cap.
- **New "Performance mode" toggle** in the Bedrock profile's Graphics settings — turn it off to manage graphics inside the game again; the setting applies from the next start.
- Measured on-device: the bundled Bedrock ran at ~15–20 fps in-world with Vibrant Visuals, 28 chunks and MSAA 2; the preset targets a steady 60 fps. `fps.log` in the session folder shows the result of every second.

## What's new in 2.1.2 — Beta Warnings & Legal

- **Beta activation warnings** — every Beta Features toggle now asks for confirmation before enabling, with a warning that the feature is experimental and may be unstable or change without notice.
- **Reworked installer license** — the pkg license screen now covers warnings (beta features, unofficial software, server hosting, third-party content), the source-code license, full credits (NeoCraft, Apple/SwiftUI, fonts, dmgbuild, Mojang, Adoptium, Fabric, Modrinth, Wine/D3DMetal) and legal/disclaimer terms.
- **Updated credits & legal sections** in the release notes and README.

## What's new in 2.1.1 — Bedrock Integration, Server Management & Liquid Glass

- **Bedrock Edition in the main app** — the bundled NeoCraft Bedrock launcher (Wine + D3DMetal) now lives inside NeoCraft; worlds, packs, screenshots and launcher state stay in sync.
- **Bedrock Dedicated Server hosting (beta)** — create and run a Windows BDS through Wine right from the Servers tab: pinned versions or latest, EULA handled, full lifecycle controls.
- **Servers tab rebuilt for hosted servers only** — create Java servers (Vanilla, Paper, Fabric) or Bedrock servers; empty world or copy a world from any instance.
- **Extensions per server type** — Paper gets Plugins, Fabric gets Mods, Vanilla gets Resource Packs; install from Modrinth search, a direct URL, or a local file.
- **Server presets** — apply curated `server.properties` profiles (Survival, Creative, Minigame, Hardcore, SMP) to Java and Bedrock servers in one click.
- **Server organization** — group servers, assign accent colors, everything persists.
- **World import/export** — download a server's world as a `.zip` or replace it from an archive (previous world is backed up first).
- **Update checks** — Vanilla compares against Mojang's latest release, Paper against the newest build, Bedrock against the BDS API; one-click update in the dashboard.
- **Play dashboard widget** — hosted servers at a glance with start/stop and a jump into the dashboard; dashboard presets (Clean, Minimal, Full, Telemetry) for a cleaner layout.
- **In-game UI is now beta-gated** — the `neocraft-ui` theme/menu mod syncs with Studio only when the beta flag is on.
- **Liquid Glass** — new app icon and a Liquid Glass appearance option in the Bedrock launcher; wallpaper effects (Aurora, Cherry Petals, End Sky, Nether Embers) ported to the launcher.
- **Minecraft font everywhere** — Silkscreen pixel font across the whole launcher UI.
- **Bedrock launcher stays open** after Minecraft exits; Screenshots/Servers/Studio tabs removed — everything is managed in NeoCraft.
- **Onboarding** — new Look step (accent, wallpaper, true black) during first run.
- **Beta toggles** — Bedrock Edition and Bedrock Server Hosting are now independent switches in Settings → Beta Features; disabling Bedrock hides all Bedrock UI.
- **BDS download fix** — migrated off the sunsetted Mojang endpoint with a mirror fallback.

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

## Warnings

- **Beta features are experimental** — enabling any beta toggle in Settings asks for confirmation first; beta features may be unstable, break saves, or change without notice.
- **Unofficial software** — community launcher, not affiliated with Mojang, Microsoft, Fabric or Modrinth. Minecraft is a trademark of Mojang Synergies AB.
- **No warranty** — provided "as is" without warranty of any kind; see the installer license for full terms.
- **Account required** — a legitimate Minecraft account (Microsoft sign-in) is required.
- **Hosted servers** — intended for personal, non-commercial use; public/monetized servers may need additional licenses or comply with Mojang's EULA.
- **Third-party content** — runtimes, mods, packs and server software downloaded at runtime belong to Mojang, Adoptium, Fabric, Modrinth and others under their own licenses.

## Credits

- **NeoCraft** — design, code and packaging by the NeoCraft project
- **Swift / SwiftUI** — Apple Inc.
- **Fonts** — PressStart2P by CodeMan38, Silkscreen by Jason Kottke (free for any use)
- **dmgbuild** — dmgbuild/dmgbuild contributors (DMG packaging)
- **Mojang Synergies AB** — Minecraft, versions, assets, server.jar, Bedrock Dedicated Server
- **Eclipse Adoptium** — Temurin Java runtimes
- **Fabric MC** — Fabric Loader and loader ecosystem
- **Modrinth** — mod/plugin/resource-pack index and API
- **Wine / D3DMetal** — runs the Windows version of Minecraft Bedrock and BDS on macOS
- **Minecraft, Fabric, Modrinth and all in-game content** belong to their respective owners
