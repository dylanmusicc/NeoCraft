#!/usr/bin/env bash
# Baut ein .pkg-Installationsprogramm aus build/NeoCraft.app.
# Installiert NeoCraft.app nach /Applications — kein Drag & Drop nötig.
# Das Installer-Design (Hintergrund, Welcome/Conclusion-Screens) folgt
# der NeoCraft-Gestaltung aus scripts/GenerateInstallerBackground.swift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/NeoCraft.app"
STAGE="$ROOT/build/pkg-stage"
PAYLOAD="$ROOT/build/pkg-payload"
COMPONENT_DIR="$ROOT/build/pkg-component"
COMPONENT_PKG="$COMPONENT_DIR/NeoCraft-component.pkg"
RES="$ROOT/build/pkg-resources"
DIST_XML="$ROOT/build/NeoCraft-distribution.xml"
VERSION="$(sed -n 's/.*version = "\(.*\)".*/\1/p' "$ROOT/Sources/NeoCraft/Core/AppConstants.swift" | head -1)"
BUNDLE_ID="com.neocraft.launcher"
OUT="$ROOT/build/NeoCraft-${VERSION}.pkg"

[[ -d "$APP" ]] || { echo "build/NeoCraft.app fehlt — zuerst ./build.sh ausführen" >&2; exit 1; }
[[ -n "$VERSION" ]] || { echo "error: konnte Version nicht aus AppConstants.swift lesen" >&2; exit 1; }

echo "==> Stage Installations-Payload"
rm -rf "$STAGE" "$PAYLOAD" "$COMPONENT_DIR" "$RES"
mkdir -p "$STAGE/Applications" "$PAYLOAD" "$COMPONENT_DIR" "$RES"
# ditto erhält Symlinks und die Signaturen der verschachtelten Bundles
# (NeoCraft Bedrock.app muss seine eigene Signatur behalten).
ditto "$APP" "$STAGE/Applications/NeoCraft.app"

echo "==> Generiere Installer-Assets im NeoCraft-Design"
BG_JPG="$RES/background.jpg"
xcrun --sdk macosx swift "$ROOT/scripts/GenerateInstallerBackground.swift" \
  "$BG_JPG" "$VERSION"
# productbuild liefert nur per Distribution-XML referenzierte Dateien mit —
# das Hintergrundbild wird daher als data-URI in die HTML-Screens eingebettet.
BG_B64="$(base64 -i "$BG_JPG" | tr -d '\n')"
# App-Icon für die Welcome/Conclusion-Cards — ebenfalls als data-URI,
# weil productbuild nur XML-referenzierte Ressourcen mitliefert.
ICON_PNG="$RES/icon-128.png"
sips -s format png -z 128 128 "$APP/Contents/Resources/AppIcon.icns" \
  --out "$ICON_PNG" >/dev/null
ICON_B64="$(base64 -i "$ICON_PNG" | tr -d '\n')"
ls -l "$ICON_PNG"
# Pixel-Font für Headlines — Silkscreen ist die Display-Schrift des
# Launchers und wird ebenfalls als data-URI eingebettet.
FONT_B64="$(base64 -i "$ROOT/Resources/Fonts/Silkscreen-Bold.ttf" | tr -d '\n')"

cat > "$RES/welcome.html" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  @font-face {
    font-family: "Silkscreen";
    src: url("data:font/ttf;base64,${FONT_B64}") format("truetype");
  }
  html, body { margin: 0; padding: 0; height: 100%; }
  body {
    background: url("data:image/jpeg;base64,${BG_B64}") center / cover no-repeat;
    font-family: -apple-system, "Helvetica Neue", sans-serif;
    color: #fff;
    display: flex; align-items: center;
  }
  .card {
    position: relative;
    margin-left: 48px;
    background: rgba(8, 18, 12, 0.78);
    border: 1px solid rgba(74, 222, 128, 0.35);
    border-radius: 14px;
    padding: 26px 32px 28px;
    max-width: 500px;
    backdrop-filter: blur(14px);
    -webkit-backdrop-filter: blur(14px);
    box-shadow: 0 18px 50px rgba(0,0,0,0.5);
  }
  .card::before {
    content: ""; position: absolute; top: 0; left: 0; right: 0; height: 4px;
    background: linear-gradient(90deg, #4ADE80 0%, #22C55E 45%, #A78BFA 100%);
    border-radius: 14px 14px 0 0;
  }
  .voxels { display: flex; gap: 5px; margin-bottom: 16px; }
  .voxels i { width: 9px; height: 9px; background: #4ADE80; }
  .voxels i:nth-child(2) { background: #22C55E; }
  .voxels i:nth-child(3) { background: #A78BFA; opacity: 0.85; }
  .icon { width: 64px; height: 64px; border-radius: 15px; margin-bottom: 12px;
          box-shadow: 0 6px 18px rgba(0,0,0,0.45); }
  h1 { font-family: "Silkscreen", sans-serif; font-size: 21px; font-weight: 700;
       margin: 0 0 8px; letter-spacing: 0.5px; }
  .ver { color: #4ADE80; font-family: "Silkscreen", sans-serif;
         font-size: 11px; letter-spacing: 1px; margin-bottom: 16px; }
  p { font-size: 14px; line-height: 1.55; color: rgba(255,255,255,0.82); margin: 0 0 10px; }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; margin: 14px 0 6px; }
  .chip { font-family: "Silkscreen", sans-serif; font-size: 9px; letter-spacing: 0.5px;
          padding: 4px 9px; border-radius: 6px;
          background: rgba(74,222,128,0.12); border: 1px solid rgba(74,222,128,0.32);
          color: #BBF7D0; }
  .chip.alt { background: rgba(167,139,250,0.12); border-color: rgba(167,139,250,0.35);
              color: #DDD6FE; }
  .hint { font-size: 12.5px; color: rgba(255,255,255,0.55); }
  .req { font-size: 12px; color: rgba(255,255,255,0.45); margin-top: 14px;
         border-top: 1px solid rgba(255,255,255,0.12); padding-top: 10px; }
  .kbd {
    display: inline-block; padding: 1px 7px; border-radius: 5px;
    background: rgba(255,255,255,0.12); border: 1px solid rgba(255,255,255,0.2);
    font-size: 11.5px; font-family: ui-monospace, Menlo, monospace;
  }
</style>
</head>
<body>
  <div class="card">
    <div class="voxels"><i></i><i></i><i></i></div>
    <img class="icon" src="data:image/png;base64,${ICON_B64}" alt="NeoCraft">
    <h1>Willkommen bei NeoCraft</h1>
    <div class="ver">VERSION ${VERSION} · NATIVE MINECRAFT LAUNCHER</div>
    <p>Dieser Installer richtet NeoCraft unter <b>/Applications</b> ein —
       inklusive NeoCraft Bedrock, dem Fabric-Leistungsmod und allen Sprachdateien.</p>
    <div class="chips">
      <span class="chip">JAVA 21/25</span>
      <span class="chip">FABRIC</span>
      <span class="chip">NEO BOOST</span>
      <span class="chip alt">BEDROCK</span>
      <span class="chip alt">MODRINTH</span>
      <span class="chip alt">6 SPRACHEN</span>
    </div>
    <p class="hint" style="margin-top:14px">Nach der Installation einmal öffnen. Falls macOS warnt:
       Rechtsklick auf NeoCraft → <span class="kbd">Öffnen</span></p>
    <p class="req">Erfordert macOS 14 oder neuer · Apple Silicon (arm64)</p>
  </div>
</body>
</html>
EOF

cat > "$RES/conclusion.html" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  @font-face {
    font-family: "Silkscreen";
    src: url("data:font/ttf;base64,${FONT_B64}") format("truetype");
  }
  html, body { margin: 0; padding: 0; height: 100%; }
  body {
    background: url("data:image/jpeg;base64,${BG_B64}") center / cover no-repeat;
    font-family: -apple-system, "Helvetica Neue", sans-serif;
    color: #fff;
    display: flex; align-items: center;
  }
  .card {
    position: relative;
    margin-left: 48px;
    background: rgba(8, 18, 12, 0.78);
    border: 1px solid rgba(74, 222, 128, 0.35);
    border-radius: 14px;
    padding: 26px 32px 28px;
    max-width: 500px;
    backdrop-filter: blur(14px);
    -webkit-backdrop-filter: blur(14px);
    box-shadow: 0 18px 50px rgba(0,0,0,0.5);
  }
  .card::before {
    content: ""; position: absolute; top: 0; left: 0; right: 0; height: 4px;
    background: linear-gradient(90deg, #4ADE80 0%, #22C55E 45%, #A78BFA 100%);
    border-radius: 14px 14px 0 0;
  }
  .voxels { display: flex; gap: 5px; margin-bottom: 16px; }
  .voxels i { width: 9px; height: 9px; background: #4ADE80; }
  .voxels i:nth-child(2) { background: #22C55E; }
  .voxels i:nth-child(3) { background: #A78BFA; opacity: 0.85; }
  .icon { width: 64px; height: 64px; border-radius: 15px; margin-bottom: 12px;
          box-shadow: 0 6px 18px rgba(0,0,0,0.45); }
  h1 { font-family: "Silkscreen", sans-serif; font-size: 19px; font-weight: 700;
       margin: 0 0 12px; letter-spacing: 0.5px; }
  p { font-size: 14px; line-height: 1.55; color: rgba(255,255,255,0.82); margin: 0 0 10px; }
  .ok { color: #4ADE80; font-family: "Silkscreen", sans-serif;
        font-size: 11px; letter-spacing: 1px; font-weight: 700; }
  .steps { margin: 14px 0 0; padding: 0; list-style: none; counter-reset: step; }
  .steps li { counter-increment: step; font-size: 13.5px; margin-bottom: 8px;
              color: rgba(255,255,255,0.78); padding-left: 26px; position: relative; }
  .steps li::before {
    content: counter(step); position: absolute; left: 0; top: 1px;
    width: 18px; height: 18px; border-radius: 5px;
    background: rgba(74,222,128,0.15); border: 1px solid rgba(74,222,128,0.4);
    color: #4ADE80; font-family: "Silkscreen", sans-serif;
    font-size: 10px; display: flex; align-items: center; justify-content: center;
  }
</style>
</head>
<body>
  <div class="card">
    <div class="voxels"><i></i><i></i><i></i></div>
    <img class="icon" src="data:image/png;base64,${ICON_B64}" alt="NeoCraft">
    <h1>Installation abgeschlossen</h1>
    <p class="ok">NEOCRAFT ${VERSION} · IN /APPLICATIONS INSTALLIERT</p>
    <ol class="steps">
      <li>Starte NeoCraft aus dem Applications-Ordner oder der Dock.</li>
      <li>Melde dich unter <b>Settings</b> mit deinem Microsoft-Konto an.</li>
      <li>Erstelle eine Instanz und drück <b>Play</b> — Java wird automatisch eingerichtet.</li>
    </ol>
    <p style="margin-top:14px">Tipp: Im Spiel <span style="font-family:ui-monospace,Menlo,monospace">Right Shift</span> öffnet den HUD-Editor, <span style="font-family:ui-monospace,Menlo,monospace">F8</span> schaltet das HUD um.</p>
  </div>
</body>
</html>
EOF

cat > "$RES/readme.txt" <<EOF
NeoCraft ${VERSION}

Native Minecraft: Java Edition Launcher für macOS (Apple Silicon).

Installation: Diese App wurde über das NeoCraft-Installationsprogramm
in /Applications abgelegt. Ein Doppelklick genügt — kein Auspacken nötig.

Erster Start:
1. Melde dich mit deinem Microsoft-Konto an (Settings).
2. Erstelle eine Instanz (Mojang-Version, Vanilla oder Fabric).
3. Drück Play — das richtige Eclipse-Temurin-JDK wird automatisch
   nach ~/Library/Application Support/NeoCraft/runtime geladen.

Tipp: Im Spiel Right Shift = HUD-Editor, F8 = HUD an/aus.

Credits: NeoCraft-Projekt · Fonts: PressStart2P (CodeMan38),
Silkscreen (Jason Kottke) · DMG-Tooling: dmgbuild

Warnung: Inoffizielle Software, nicht mit Mojang oder Microsoft
verbunden. Wird "wie besehen" ohne Gewähr bereitgestellt.
Zum Spielen ist ein legitimer Minecraft: Java Edition-Account nötig.
Die App ist ad-hoc signiert — beim ersten Start ggf. Rechtsklick →
Öffnen wählen (Gatekeeper-Hinweis).

NeoCraft ist ein unabhängiges Projekt und steht in keiner Verbindung
zu Mojang, Microsoft, Fabric oder Modrinth.
EOF

cat > "$RES/license.txt" <<EOF
NeoCraft ${VERSION} — Lizenz- und Haftungshinweis

Der NeoCraft-Quellcode in diesem Repository steht zur persönlichen
Nutzung und zum Lernen zur Verfügung.

NeoCraft ist ein unabhängiges Projekt. Es besteht keine Verbindung,
Billigung oder Partnerschaft mit Mojang Studios, Microsoft, Fabric
oder Modrinth. Minecraft ist eine Marke von Mojang Synergies AB.
Zum Spielen ist ein legitimer Minecraft: Java Edition-Account
erforderlich.

Von NeoCraft oder durch die Nutzung der Software geladene
Drittanbieter-Inhalte und -Laufzeiten unterliegen ihren jeweiligen
Lizenzen:

- Minecraft-Metadaten und Assets: Mojang
- Java-Laufzeit: Eclipse Temurin / Adoptium
- Mod-Loader: Fabric MC
- Mods und Projektdaten: Modrinth und deren Autorinnen und Autoren

Die Software wird "wie besehen" ohne Gewährleistung jeglicher Art
bereitgestellt. In keinem Fall haften die Autorinnen und Autoren für
Schäden, die aus der Nutzung entstehen.
EOF

cat > "$DIST_XML" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>NeoCraft ${VERSION}</title>
    <organization>${BUNDLE_ID}</organization>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <license file="license.txt" mime-type="text/plain"/>
    <readme file="readme.txt" mime-type="text/plain"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <choices-outline>
        <line choice="default">
            <line choice="NeoCraft.app"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="NeoCraft.app" visible="false">
        <pkg-ref id="com.neocraft.launcher.pkg"/>
    </choice>
    <pkg-ref id="com.neocraft.launcher.pkg" version="${VERSION}" onConclusion="none">NeoCraft-component.pkg</pkg-ref>
</installer-gui-script>
EOF

echo "==> Erzeuge Komponenten-Paket"
pkgbuild \
  --root "$STAGE" \
  --identifier "${BUNDLE_ID}.pkg" \
  --version "${VERSION}" \
  --install-location "/" \
  "$COMPONENT_PKG"

echo "==> Erzeuge Produkt-Paket (GUI-Installer)"
rm -f "$OUT"
productbuild \
  --distribution "$DIST_XML" \
  --resources "$RES" \
  --package-path "$COMPONENT_DIR" \
  "$OUT"

# Hinweis: productsign benötigt ein echtes Zertifikat — für lokale Builds
# bleibt das Paket unsigniert. Die App im Bundle ist weiterhin ad-hoc signiert.
echo
echo "Fertig: $OUT"
echo "Installieren mit: open \"$OUT\"  (oder: sudo installer -pkg \"$OUT\" -target /)"
echo "Größe: $(du -sh "$OUT" | cut -f1)"
