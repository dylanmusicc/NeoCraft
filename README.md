<div align="center">

<img src="https://img.shields.io/badge/macOS-14%2B-black?style=for-the-badge&logo=apple" alt="macOS 14+">
<img src="https://img.shields.io/badge/Apple_Silicon-arm64-4ADE80?style=for-the-badge&logo=apple" alt="Apple Silicon">
<img src="https://img.shields.io/badge/Swift-6-FBBF24?style=for-the-badge&logo=swift" alt="Swift 6">
<img src="https://img.shields.io/badge/Version-2.0.0-7C3AED?style=for-the-badge" alt="v2.0.0">

# ⛏️ NeoCraft

### *Der native Minecraft-Launcher, den dein Mac verdient hat.*

**Minecraft: Java Edition — paved with Swift, fueled by magic.**

Ein Launch-Pad in Swift 6 + SwiftUI, gebaut für Apple Silicon und leise 8-GB-Macs.
Microsoft-Anmeldung, Mojang-Versionen, Fabric, Java-Installation, Modrinth —
alles wie von Zauberhand.

</div>

---

## ✨ Was NeoCraft kann

| | |
|---|---|
| 🎮 **Ein-Klick-Play** | Microsoft Device-Code-Login, Mojang-Versionen, Fabric-Loader, Neo Boost — bereit in einem Atemzug. |
| ☕ **Java, automatisch** | Eclipse Temurin JDK 21/25 wird selbstständig geladen — passgenau zur Minecraft-Version. |
| 📦 **Mod Library** | Modrinth-Suche mit Versions- & Fabric-Filtern, Dependency-Auflösung, One-Click-Install. |
| 🌍 **6 Sprachen** | Englisch, British English, Deutsch, Spanisch, Französisch, Russisch. |
| 🛏️ **Bedrock (Beta)** | Minecraft für Windows läuft nativ über Wine + D3DMetal — direkt aus der App. |
| 🎨 **Studio** | Themes, Wallpapers, Akzente, Grid — dein Launcher, dein Stil. Frosted Glass bis OLED Dark. |
| 🌡️ **Kühl & leise** | 4,5 GB Heap, G1GC-Tuning, FPS-Cap & Render-Distance — dein MacBook bleibt kühl. |
| 📡 **Server Radar** | Server-Liste mit Live-Ping direkt im Launcher. |

---

## 🚀 Schnellstart — 60 Sekunden bis zum Bauen

```bash
# 1. NeoCraft holen
curl -LO https://github.com/dylanmusicc/NeoCraft/releases/latest/download/NeoCraft-2.0.0.pkg

# 2. Installieren (zieht die App nach /Applications)
open NeoCraft-2.0.0.pkg
```

> **Erster Start:** macOS fragt einmal nach Erlaubnis — **Rechtsklick → Öffnen**.
> Der Build ist ad-hoc signiert; mehr dazu unter [⚠️ Hinweise](#-warnungen--hinweise).

Dann: **Settings → Microsoft-Konto anmelden → Instanz erstellen → PLAY.**
Das richtige JDK lädt sich von allein. Fertig.

<details>
<summary>🖼️ Alternativ: DMG (Drag & Drop)</summary>

```bash
curl -LO https://github.com/dylanmusicc/NeoCraft/releases/latest/download/NeoCraft-2.0.0.dmg
open NeoCraft-2.0.0.dmg
# NeoCraft.app auf den Applications-Ordner ziehen
```

</details>

---

## 🏗️ Aus dem Quellcode bauen

Voraussetzungen: macOS 14+, Apple Silicon, Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/dylanmusicc/NeoCraft.git
cd NeoCraft
./build.sh          # baut build/NeoCraft.app
./build.sh --run    # baut und startet sofort
```

### Distribution-Artefakte

```bash
./scripts/MakePKG.sh   # → build/NeoCraft-<version>.pkg  (GUI-Installer)
./scripts/MakeDMG.sh   # → build/NeoCraft-<version>.dmg  (Drag & Drop)
```

Beide Installer tragen das NeoCraft-Design: Forest-Gradient, isometrischer
Grasblock, Pixel-Wordmark, App-Icon und die Silkscreen-Pixel-Schrift.
`MakeDMG.sh` braucht `python3 -m pip install dmgbuild` — der AppleScript-Weg
für DMG-Hintergründe ist seit macOS 26 kaputt.

---

## 🗺️ Architektur

```
Sources/NeoCraft/
├── App/           AppModel (Observable-Koordinator), App-Einstieg
├── Core/          Pfade, Netzwerk, Downloader, Persistenz, Keychain,
│                  System-Metriken, Logging, Instance-Scanner
├── Models/        Settings, Instanzen, Mojang/Fabric/Modrinth-DTOs
├── Services/
│   ├── Auth/      Microsoft Device-Code → Xbox Live → XSTS → Minecraft
│   ├── Game/      Versionsmanifest, Installer, Java-Manager,
│   │              Launch-Planer, Options-Tweaker, Prozess-Supervision
│   └── Modrinth/  v2-API, Dependency-Resolver, Neo-Boost-Installer
└── Views/         Root, Sidebar, vier Produkt-Bereiche, Sheets,
                   Design-System
```

**Concurrency:** Swift 6 Strict Concurrency — Services sind Actors,
UI-State ist `@MainActor @Observable`, Downloads laufen über ein
geteiltes `URLSession`-Fast-Path plus Delegate-Session mit Fortschritt.

**Daten:** Alles liegt in `~/Library/Application Support/NeoCraft/`
(State, Shared-Libraries, Runtime-JDKs, Instanzen, Logs). Tokens
sicher im **macOS Keychain**, nie in `state.json`.

---

## 🎮 Im Spiel

| Taste | Aktion |
|---|---|
| `Right Shift` | HUD-Editor öffnen |
| `F8` | HUD an/aus |

Performance-Defaults: `-Xmx4608M`, G1GC, `AlwaysPreTouch`, 60 FPS-Cap,
10-Chunks Render-Distance — optimiert für passiv gekühlte MacBooks.
Minecraft 1.20.5+ wird direkt in `options.txt` konfiguriert.

---

## ⚠️ Warnungen & Hinweise

- **Inoffizielle Software** — NeoCraft ist ein Community-Launcher, kein offizielles Mojang/Microsoft-Produkt. Nutzung auf eigene Gefahr.
- **Keine Gewähr** — „as is" ohne Garantie. Details im Lizenz-Screen des Installers.
- **Account nötig** — ein legitimer Minecraft: Java Edition-Account (Microsoft-Login) ist erforderlich.
- **Ad-hoc signiert** — nicht notarisiert; Gatekeeper fragt beim ersten Start (Rechtsklick → Öffnen oder `xattr -cr`).
- **Drittanbieter-Downloads** — JDKs, Libraries, Mods und Assets werden zur Laufzeit von Mojang, Adoptium, Fabric und Modrinth geladen — jeweils unter deren Lizenzen.
- **Bedrock (Beta)** — benötigt macOS 27 und einen Microsoft-Account mit Minecraft für Windows.

## 📜 Rechtliches

Minecraft ist eine Marke von Mojang Synergies AB. NeoCraft steht in
keiner Verbindung zu Mojang, Microsoft, Fabric oder Modrinth.
Vollständige Hinweise: [`RELEASE_NOTES.md`](RELEASE_NOTES.md) und der
Lizenz-Screen im Installer.

## 🙏 Credits

- **NeoCraft** — Design, Code & Packaging vom NeoCraft-Projekt
- **Swift / SwiftUI** — Apple
- **Fonts** — PressStart2P by CodeMan38 · Silkscreen by Jason Kottke
- **dmgbuild** — dmgbuild contributors (DMG-Packaging)
- **Minecraft, Fabric, Modrinth** — und alle In-Game-Inhalte gehören ihren jeweiligen Eigentümern

---

<div align="center">

**⛏️ Craft it. Play it. NeoCraft it.**

<sub>Made with Swift on Apple Silicon · Not affiliated with Mojang or Microsoft</sub>

</div>
