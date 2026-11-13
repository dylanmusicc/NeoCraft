#!/bin/sh
# build-app.sh: build dist/NeoCraft Bedrock.app from a built engine, with the Command Line Tools alone.
#
# The launcher and its account service are signed with the local self-signed identity: the service
# serves only a launcher signed with its own certificate. The engine and D3DMetal go inside the app,
# sealed by its signature. Run scripts/build.sh instead unless the engine is already built.
#
# Environment: SB_WORK (where builds go, see build.sh), SIGNING_IDENTITY.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${SB_WORK:-/private/tmp/siliconbedrock-build}
IDENTITY=${SIGNING_IDENTITY:-SiliconBedrock Local}
PACKAGES=$WORK/engine/packages
VERSION=$(cat "$ROOT/VERSION")
ENGINE_VERSION=$(cat "$ROOT/engine/VERSION")
GPTK=$ROOT/third_party/gptk-4.0b3
APP=$ROOT/dist/NeoCraft Bedrock.app
CONTENTS=$APP/Contents
RESOURCES=$CONTENTS/Resources

die() { printf 'build-app: %s\n' "$*" >&2; exit 1; }

[ -f "$PACKAGES/index.json" ] || die "no engine in $PACKAGES; run scripts/build.sh"
[ -f "$GPTK/lib/external/libd3dshared.dylib" ] || die "no D3DMetal in $GPTK"
# Without -v: a self-signed certificate isn't "valid" to macOS, and signs just the same.
security find-identity -p codesigning | grep -q "\"$IDENTITY\"" ||
  die "no signing identity \"$IDENTITY\"; run scripts/signing-identity.sh"

"$ROOT/scripts/vendor-engine.sh" "$ENGINE_VERSION" --from "$PACKAGES"
SERVICE=$ROOT/Vendor/engine

printf '==> Building the launcher\n'
# The paths the compiler records are remapped, so that the binary doesn't name the builder's folders.
swift build --package-path "$ROOT" --scratch-path "$WORK/app" -c release --product SiliconBedrock \
  -Xswiftc -file-prefix-map -Xswiftc "$ROOT=/NeoCraftBedrock" \
  -Xswiftc -file-prefix-map -Xswiftc "$HOME=/builder"
BIN=$(swift build --package-path "$ROOT" --scratch-path "$WORK/app" -c release --show-bin-path)

printf '==> Assembling %s\n' "$APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers" "$RESOURCES/Engine" "$RESOURCES/GPTK"
cp "$BIN/SiliconBedrock" "$CONTENTS/MacOS/SiliconBedrock"
strip -S -x "$CONTENTS/MacOS/SiliconBedrock"
cp "$ROOT/Config/Info.plist" "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"
cp "$ROOT/Config/AppIcon.icns" "$ROOT/LICENSE" "$ROOT/NOTICE.md" "$RESOURCES/"
cp -R "$BIN/SwiftProtobuf_SwiftProtobuf.bundle" "$RESOURCES/"
mkdir -p "$RESOURCES/Fonts"
cp "$ROOT/Config/Fonts/"*.ttf "$RESOURCES/Fonts/"
# Localizations: each <lang>.lproj holds Localizable.strings for String(localized:).
for lproj in "$ROOT"/Config/L10n/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$RESOURCES/"
done

cp "$SERVICE/xodus-service" "$CONTENTS/Helpers/xodus-service"
cp "$SERVICE/service-pin.json" "$RESOURCES/Engine/"
cp -R "$SERVICE/Licenses" "$RESOURCES/Engine/"
cp "$PACKAGES/index.json" "$PACKAGES/macrock-engine-$ENGINE_VERSION.aar" "$RESOURCES/Engine/"

# Apple's files as Apple made them: symbolic links and signatures matter.
ditto "$GPTK" "$RESOURCES/GPTK"
rm -f "$RESOURCES/GPTK/README.md"

printf '==> Signing with "%s"\n' "$IDENTITY"
codesign --force --options runtime --timestamp=none --identifier dev.siliconbedrock.launcher \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
codesign --verify --strict "$CONTENTS/Helpers/xodus-service"
printf '==> %s: %s\n' "$APP" "$(du -sh "$APP" | cut -f 1)"
