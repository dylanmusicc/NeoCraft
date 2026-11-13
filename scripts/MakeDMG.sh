#!/usr/bin/env bash
# Baut ein stylisches .dmg aus build/NeoCraft.app.
#
# Hintergrundbild, Icon-Positionen und .DS_Store werden von dmgbuild
# direkt geschrieben — der bisherige AppleScript-Weg
# ("set background picture") ist seit macOS 26/Tahoe kaputt (-10006).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/NeoCraft.app"
WORK="$ROOT/build/dmg-work"
BG="$WORK/background.png"
VOLICON="$WORK/.VolumeIcon.icns"
SETTINGS="$WORK/dmgbuild_settings.py"
VERSION="$(sed -n 's/.*version = "\(.*\)".*/\1/p' "$ROOT/Sources/NeoCraft/Core/AppConstants.swift" | head -1)"
VOLUME="NeoCraft ${VERSION}"
OUT="$ROOT/build/NeoCraft-${VERSION}.dmg"
OLD_DMG="$ROOT/build/NeoCraft.dmg"

[[ -d "$APP" ]] || { echo "build/NeoCraft.app fehlt — zuerst ./build.sh ausführen" >&2; exit 1; }
[[ -n "$VERSION" ]] || { echo "error: konnte Version nicht aus AppConstants.swift lesen" >&2; exit 1; }
command -v python3 >/dev/null || { echo "error: python3 nicht gefunden" >&2; exit 1; }
python3 -c "import dmgbuild" 2>/dev/null || {
  echo "==> Installiere dmgbuild (pip)"
  python3 -m pip install --user dmgbuild
}

echo "==> Generiere DMG-Hintergrund"
mkdir -p "$WORK"
xcrun --sdk macosx swift "$ROOT/scripts/GenerateDMGBackground.swift" \
  "$BG" "$VERSION"
# Finder interpretiert DMG-Hintergründe in 72-dpi — sonst verschiebt sich
# die Darstellung.
sips -s dpiWidth 72 -s dpiHeight 72 "$BG" --out "$BG" >/dev/null

# .VolumeIcon.icns → eigenes NeoCraft-Icon für das DMG-Volume.
cp "$APP/Contents/Resources/AppIcon.icns" "$VOLICON"

cat > "$SETTINGS" <<'PYEOF'
application = defines.get("app")
background = defines.get("background")
volicon = defines.get("volicon")

format = "UDZO"
files = [application, volicon]
symlinks = {"Applications": "/Applications"}

# Hintergrund ist 760x440 px — Fenster und Icon-Positionen richten sich
# daran aus (Icon-Koordinaten sind die Icon-Mitten, „Applications" ist
# der Symlink und taucht nicht als Datei im DMG auf).
icon_size = 96
window_rect = ((200, 120), (760, 440))
icon_locations = {
    "NeoCraft.app": (215, 275),
    "Applications": (545, 275),
}
PYEOF

echo "==> Erzeuge DMG"
rm -f "$OUT" "$OLD_DMG"
python3 -m dmgbuild \
  -s "$SETTINGS" \
  -D "app=$APP" \
  -D "background=$BG" \
  -D "volicon=$VOLICON" \
  "$VOLUME" \
  "$OUT"

# Altes unversioniertes Artefakt mitziehen (Kompatibilität).
cp "$OUT" "$OLD_DMG"

rm -rf "$WORK"

echo
echo "Fertig: $OUT"
echo "Größe: $(du -sh "$OUT" | cut -f1)"
