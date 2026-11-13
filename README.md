# NeoCraft

A native macOS Minecraft: Java Edition launcher built with Swift 6 and SwiftUI, tuned for Apple silicon and 8 GB Macs.

NeoCraft handles the whole lifecycle for you: Microsoft sign-in, Mojang version resolution, Fabric, Java discovery and installation, concurrent asset downloads, Modrinth content, and a quiet performance profile that keeps fanless MacBooks comfortable.

```
┌──────────────────────────────────────────────────────────────┐
│  Play        Instances        Mod Library        Settings    │
│                                                              │
│  Microsoft device-code auth   Mojang + Fabric + Modrinth     │
│  Automatic Eclipse Temurin    Java 21 / 25, arm64 native     │
│  Neo Boost Fabric preset      Sodium, Lithium, FerriteCore   │
└──────────────────────────────────────────────────────────────┘
```

## Requirements

- macOS 14 Sonoma or newer
- Apple silicon Mac (arm64 build target)
- Swift 6 toolchain from the Xcode Command Line Tools
- An internet connection for the first launch
- A Microsoft account that owns Minecraft: Java Edition

No Xcode project or App Sandbox is required. NeoCraft is a Swift Package Manager executable bundled into a normal `.app`.

## Install

**macOS installer (.pkg, recommended)**

1. Download `NeoCraft-<version>.pkg` from the Releases page and double-click it.
2. The installer places NeoCraft.app in `/Applications` — no dragging required.
3. Because the app is not notarized with an Apple Developer ID yet, right-click NeoCraft.app and select Open on the first launch (or run `xattr -cr /Applications/NeoCraft.app` in Terminal).

**Disk image (.dmg)**

1. Download `NeoCraft-<version>.dmg`, open it and drag NeoCraft.app into the Applications folder.
2. Same first-launch step as above.

Then sign in with your Microsoft account under Settings, create an instance, and hit Play!
For Bedrock instances, make sure `Sources/NeoCraft Bedrock` was built (`scripts/build.sh` inside it) before running `./build.sh`, so the Bedrock component is bundled.

## Build

```bash
chmod +x build.sh
./build.sh
open build/NeoCraft.app
```

`./build.sh --run` builds and opens the app in one step.

### Distribution artifacts

Two styled installers are produced from `build/NeoCraft.app`:

```bash
./scripts/MakePKG.sh   # build/NeoCraft-<version>.pkg — GUI installer → /Applications
./scripts/MakeDMG.sh   # build/NeoCraft-<version>.dmg — drag-to-Applications image
```

Both use the NeoCraft visual language (forest gradient, isometric grass
block, pixel wordmark). The DMG background is rendered by
`scripts/GenerateDMGBackground.swift`; the PKG welcome/conclusion screens
by `scripts/GenerateInstallerBackground.swift` plus embedded app icon,
background and the bundled Silkscreen pixel font.

Note: `MakeDMG.sh` requires `dmgbuild` (`python3 -m pip install dmgbuild`)
because Finder's AppleScript `background picture` API stopped working in
macOS 26 — dmgbuild writes the `.DS_Store` directly instead.

The script:

1. Builds the release binary with `swift build -c release`.
2. Creates `build/NeoCraft.app/Contents/{MacOS,Resources}`.
3. Writes a complete `Info.plist`.
4. Generates a themed icon with Core Graphics and `iconutil`.
5. Ad-hoc signs the bundle with `entitlements.plist`.
6. Verifies the signature.

The result is a double-clickable app. It is ad-hoc signed, which is appropriate for local builds. Distributing it to another Mac requires a Developer ID certificate and notarization.

### Entitlements

| Entitlement | Purpose |
| --- | --- |
| `com.apple.security.network.client` | Mojang, Fabric, Adoptium, Microsoft and Modrinth HTTPS |
| `com.apple.security.cs.allow-jit` | Allows a downloaded JDK to execute |
| `com.apple.security.cs.allow-unsigned-executable-memory` | Local Java launcher compatibility |
| `com.apple.security.cs.disable-library-validation` | Allows the bundled JVM to load its own libraries |
| App Sandbox | **Disabled** so downloaded Java runtimes can execute |

## Features

### Play

- One-click launch with automatic Java, version, Fabric and Neo Boost preparation.
- Live memory, CPU, thermal and Low Power Mode telemetry.
- Activity feed with determinate download progress.
- Minecraft patch notes with full markdown detail.
- Launch planning that redacts access tokens from logs.

### Instances

- Isolated game directories for worlds, mods, resource packs, shaders and screenshots.
- Mojang release and snapshot catalog.
- Vanilla or Fabric, per-instance Java runtime, memory override, JVM/game arguments.
- Icon and accent customization.
- Duplicate, reveal in Finder, or move to the Bin.

### Mod Library

- Modrinth v2 search for mods, resource packs and shaders.
- Minecraft version and Fabric-aware filtering using the selected instance.
- One-click install with required dependency resolution.
- Installed-state tracking and removal.
- Project details with markdown body, gallery, license and compatible files.

### Neo Boost

Fabric Loader + Fabric API plus Sodium, Lithium, FerriteCore and ImmediatelyFast, resolved from Modrinth at install time. Optional per instance and applied automatically before first launch when enabled.

### Bedrock Edition (beta)

- Bedrock instances launch through **NeoCraft Bedrock**, a companion component (Wine + Xbox GDK runtime + Apple's D3DMetal) that `build.sh` bundles inside `NeoCraft.app` at `Contents/Resources/Bedrock/` when `Sources/NeoCraft Bedrock/dist/NeoCraft Bedrock.app` has been built — nothing is installed into `/Applications`.
- Pressing Play on a Bedrock instance launches the bundled component directly with `--play`: it starts the game without showing its own window. The component's UI (accounts, game install, worlds, settings) only appears when setup is needed — first run, sign-in — or via the gear button next to Play.
- Requires macOS 27 and a Microsoft account that owns Minecraft for Windows.

### Java

- Detects Homebrew, `/Library/Java/JavaVirtualMachines`, `java_home`, and NeoCraft-managed runtimes.
- Automatically downloads and extracts the matching Eclipse Temurin macOS arm64 JDK.
- Per-version required Java is read from the Mojang version manifest; current 2026 releases require Java 25.
- Manual runtime override with executable picker, plus Java 21 and 25 install buttons.
- Everything is stored in Application Support for user-writable, sandbox-free execution.

### Performance defaults

- `-Xmx4608M -Xms1024M` (4.5 GB / 1 GB)
- `-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=100`
- `-XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch`
- `-XX:StackShadowPages=32`
- Cool & Quiet: 60 FPS cap and 10-chunk render distance.
- Max Performance: uncapped frame rate with a balanced render distance.
- Minecraft 1.20.5+ options are edited directly (`options.txt`), respecting existing user settings.

## Data layout

```
~/Library/Application Support/NeoCraft/
├── state.json                 # settings, instances, account metadata
├── shared/
│   ├── versions/              # client jars, version JSON, log configs
│   ├── libraries/             # Mojang + Fabric libraries
│   └── assets/                # asset index and objects
├── runtime/                   # Eclipse Temurin JDKs managed by NeoCraft
├── instances/<UUID>/
│   ├── minecraft/             # game directory, mods, saves, options.txt
│   ├── natives/               # extracted arm64 natives
│   └── neocraft/              # installed content + Neo Boost marker
├── cache/                     # temporary download cache
└── logs/                      # launch logs and console archives
```

Microsoft refresh and access tokens are stored in the macOS Keychain, not in `state.json`.

## Architecture

```
Sources/NeoCraft/
├── App/           AppModel (observable coordinator), app entry, commands
├── Core/          paths, networking, downloader, persistence, Keychain,
│                  system metrics, logging, instance scanner
├── Models/        settings, instances, Minecraft/Fabric/Modrinth DTOs, activity
├── Services/
│   ├── Auth/      Microsoft device code -> Xbox Live -> XSTS -> Minecraft
│   ├── Game/      version manifest, installer, Java manager, launch planner,
│   │              options tweaker, process supervision
│   └── Modrinth/  v2 API client, dependency resolver, Neo Boost installer
└── Views/         Root, sidebar and the four product sections, sheets,
                   design system
```

### Concurrency

Swift 6 strict concurrency is enabled. Services are actors, the UI state is `@MainActor @Observable`, and downloads use a shared `URLSession` fast path for small files plus a delegate session for large progress-tracked archives. No whole-file reads are used for assets.

### Native libraries

Only `natives-macos-arm64` classifiers are extracted. If a library publishes an arm64 counterpart, non-arm64 variants are skipped. A launch fails with a clear error if no arm64 native exists for the current version.

## Configuration

The Microsoft public client ID used for the device-code flow can be overridden for development:

```bash
NEOCRAFT_MSA_CLIENT_ID="your-client-id" open build/NeoCraft.app
```

Environment variables must be present in the app's environment; launching from Finder will not inherit shell variables. For a permanent override, change `defaultMSAClientID` in `Core/AppConstants.swift` and rebuild.

## Troubleshooting

### The app opens but says "No Java runtime found"

Leave Java set to **Automatic** in Settings. NeoCraft downloads the correct Temurin JDK into `Application Support/NeoCraft/runtime` before the first launch. To test the download immediately, open **Settings → Java Runtime → Install Java 25**.

### A launch fails with "Couldn't launch"

Open **Play → Console** or **Settings → Console** for the full log. The latest launch log is stored in `Application Support/NeoCraft/logs`. Common causes are an expired Microsoft session, a mod that does not support the instance's Minecraft/Fabric version, or a stale manual Java path.

### A mod is missing after install

Mods install into the selected instance. Check the instance shown in the Mod Library banner. Fabric mods require the instance loader to be Fabric; NeoCraft shows a clear message when it is not.

### Reset the launcher

Moving `Application Support/NeoCraft` to the Bin removes instances, shared libraries, runtimes and logs. Accounts remain in Keychain until removed in Settings or with Keychain Access.

## Legal

NeoCraft is an independent project. It is not affiliated with, endorsed by, or associated with Mojang Studios, Microsoft, Fabric, or Modrinth. Minecraft is a trademark of Mojang Synergies AB. You must own a legitimate Minecraft: Java Edition account to play.

Third-party content and runtimes are downloaded from their official services under their respective licenses:

- Minecraft metadata and assets: Mojang
- Java runtime: Eclipse Temurin / Adoptium
- Mod loader: Fabric MC
- Mods and project metadata: Modrinth and their authors

## Credits

- **NeoCraft** — design, code and packaging by the NeoCraft project
- **Swift / SwiftUI** — Apple
- **Fonts** — PressStart2P by CodeMan38, Silkscreen by Jason Kottke (both free for any use)
- **dmgbuild** — dmgbuild/dmgbuild contributors (DMG packaging)
- **Minecraft**, **Fabric**, **Modrinth** and all in-game content belong to their respective owners

## Warnings & notices

- **Unofficial software.** NeoCraft is a community launcher, not an official Mojang or Microsoft product. Use it at your own risk.
- **No warranty.** The software is provided "as is" without warranty of any kind. See `RELEASE_NOTES.md` / the in-installer license for details.
- **Account required.** A legitimate Minecraft: Java Edition account (Microsoft sign-in) is required; NeoCraft cannot bypass authentication.
- **Ad-hoc signed.** Local builds are ad-hoc signed and not notarized. macOS Gatekeeper will warn on first launch — right-click → Open, or `xattr -cr`.
- **Third-party downloads.** NeoCraft downloads runtimes, libraries, mods and assets from Mojang, Adoptium, Fabric and Modrinth at runtime; those are governed by their own licenses.
- **Bedrock beta.** The bundled NeoCraft Bedrock component requires macOS 27 and a Microsoft account that owns Minecraft for Windows.

## License

The NeoCraft source in this repository is provided for personal use and learning. Respect the licenses of all downloaded third-party content.
