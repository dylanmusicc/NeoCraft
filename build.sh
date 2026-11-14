#!/bin/bash
set -euo pipefail

# NeoCraft build script
# Produces build/NeoCraft.app, a double-clickable, ad-hoc signed macOS app.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

APP_NAME="NeoCraft"
BUNDLE_ID="com.neocraft.launcher"
# Single source of truth for the app version is AppConstants.swift — the
# binary, User-Agent and Minecraft launcher props all read it from there.
VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' \
  "$ROOT/Sources/NeoCraft/Core/AppConstants.swift" | head -1)"
[[ -n "$VERSION" ]] || { echo "error: could not read version from AppConstants.swift" >&2; exit 1; }
BUILD_NUMBER="1"
MIN_MACOS="14.0"
APP="$ROOT/build/${APP_NAME}.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: NeoCraft must be built on macOS." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "error: Swift is not installed. Install the Xcode Command Line Tools with: xcode-select --install" >&2
  exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
  echo "error: iconutil is unavailable. Install the Xcode Command Line Tools." >&2
  exit 1
fi

# The macOS 27 SDK requires the SwiftUIMacros plugin that only ships inside
# full Xcode. When building with Command Line Tools alone, prefer the newest
# versioned SDK below 27 (e.g. MacOSX26.x.sdk) so SwiftUI property wrappers
# compile. With full Xcode installed the default SDK is fine.
SDKROOT_OVERRIDE=""
DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
FULL_XCODE=0
[[ "$DEVELOPER_DIR" == *.app/Contents/Developer ]] && FULL_XCODE=1
if [[ -n "$DEVELOPER_DIR" && -d "$DEVELOPER_DIR/SDKs" && "$FULL_XCODE" == "0" ]]; then
  BEST_SDK=""
  BEST_MAJOR=-1
  for sdk in "$DEVELOPER_DIR/SDKs/"MacOSX*.sdk; do
    [[ -e "$sdk" ]] || continue
    base="$(basename "$sdk" .sdk)"          # MacOSX26.5 / MacOSX27
    ver="${base#MacOSX}"                    # 26.5 / 27
    major="${ver%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] || continue
    # Skip SDKs at or above 27 — they need the Xcode-only macro plugin.
    [[ "$major" -ge 27 ]] && continue
    if [[ "$major" -gt "$BEST_MAJOR" ]]; then
      BEST_MAJOR="$major"
      BEST_SDK="$sdk"
    fi
  done
  if [[ -n "$BEST_SDK" ]]; then
    SDKROOT_OVERRIDE="$BEST_SDK"
    echo "==> Using SDKROOT=$SDKROOT_OVERRIDE"
  fi
fi

echo "==> Building NeoCraft in release mode"
# -Xlinker -w: the Command Line Tools inject search paths under
# $DEVELOPER_DIR/Developer that don't exist on disk; without this the link
# step prints two spurious "search path not found" warnings.
if [[ -n "$SDKROOT_OVERRIDE" ]]; then
  SDKROOT="$SDKROOT_OVERRIDE" swift build -c release --product "$APP_NAME" -Xlinker -w
else
  swift build -c release --product "$APP_NAME" -Xlinker -w
fi

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BINARY" ]]; then
  echo "error: release binary was not produced at $BINARY" >&2
  exit 1
fi

echo "==> Creating app bundle"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER}</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.games</string>
	<key>LSArchitecturePriority</key>
	<array>
		<string>arm64</string>
	</array>
	<key>LSMinimumSystemVersion</key>
	<string>${MIN_MACOS}</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>NeoCraft ${VERSION}. Not affiliated with Mojang or Microsoft.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist" >/dev/null

echo "==> Generating app icon"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift "$ROOT/scripts/GenerateIcon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Bundling fonts"
mkdir -p "$RESOURCES_DIR/Fonts"
cp "$ROOT/Resources/Fonts/"*.ttf "$RESOURCES_DIR/Fonts/"

echo "==> Bundling localizations"
cp -R "$ROOT/Resources/L10n" "$RESOURCES_DIR/L10n"

echo "==> Bundling NeoCraft Bedrock"
# The Bedrock runtime ships inside NeoCraft.app and launches in place —
# Play starts it with --play, so nothing is installed into /Applications.
# It must be built first:
#   cd "Sources/NeoCraft Bedrock" && scripts/build.sh
BEDROCK_APP="$ROOT/Sources/NeoCraft Bedrock/dist/NeoCraft Bedrock.app"
BEDROCK_DEST="$RESOURCES_DIR/Bedrock/NeoCraft Bedrock.app"
if [[ -d "$BEDROCK_APP" ]]; then
  mkdir -p "$RESOURCES_DIR/Bedrock"
  rm -rf "$BEDROCK_DEST"
  # ditto preserves symlinks and the app's own signature — the GPTK inside
  # relies on both, and xodus-service only serves a launcher signed with
  # the "SiliconBedrock Local" certificate.
  ditto "$BEDROCK_APP" "$BEDROCK_DEST"
  echo "    bundled NeoCraft Bedrock ($(du -sh "$BEDROCK_DEST" | cut -f1))"
else
  echo "warn: NeoCraft Bedrock not found at $BEDROCK_APP"
  echo "      Bedrock instances won't be installable from this build."
  echo "      Build it first: cd \"Sources/NeoCraft Bedrock\" && scripts/build.sh"
fi

echo "==> Building NeoCraft Fabric mods"
# First-party companion mods bundled into NeoCraft.app and auto-installed
# into Neo Boost Fabric instances: HUD widgets, the in-game server/host
# bridge and the NeoCraft screen theme.
MOD_DIRS=("NeoCraftHUD" "NeoCraftHost" "NeoCraftUI")
MOD_JAR_NAMES=("neocraft-hud" "neocraft-host" "neocraft-ui")
GRADLE_VERSION="9.9.1"
GRADLE_CACHE="$HOME/.neocraft/gradle"
GRADLE_HOME="$GRADLE_CACHE/gradle-$GRADLE_VERSION"

# Ensure a Gradle runtime is available: prefer the project's wrapper, then
# gradle on PATH, then a pinned distribution cached under ~/.neocraft/gradle.
ensure_gradle() {
  if command -v gradle >/dev/null 2>&1; then
    echo "    using gradle from PATH"
    return 0
  fi
  if [[ -x "$GRADLE_HOME/bin/gradle" ]]; then
    echo "    using cached Gradle $GRADLE_VERSION"
    return 0
  fi

  echo "    downloading Gradle $GRADLE_VERSION …"
  mkdir -p "$GRADLE_CACHE"
  local zip="$GRADLE_CACHE/gradle-$GRADLE_VERSION-bin.zip"
  if ! curl -fL --retry 2 -o "$zip" \
      "https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip"; then
    echo "warn: could not download Gradle $GRADLE_VERSION" >&2
    rm -f "$zip"
    return 1
  fi
  if ! unzip -q -o "$zip" -d "$GRADLE_CACHE"; then
    echo "warn: could not unpack Gradle $GRADLE_VERSION" >&2
    rm -f "$zip"
    return 1
  fi
  rm -f "$zip"
  [[ -x "$GRADLE_HOME/bin/gradle" ]] || { echo "warn: Gradle unpack incomplete" >&2; return 1; }
  echo "    cached Gradle $GRADLE_VERSION at $GRADLE_HOME"
  return 0
}

gradle_cmd() {
  # Runs `gradle <args>` inside the given mod directory, preferring the
  # project wrapper, then a cached distribution, then PATH.
  local dir="$1"; shift
  if [[ -x "$dir/gradlew" ]]; then
    (cd "$dir" && ./gradlew --quiet "$@")
  elif [[ -x "$GRADLE_HOME/bin/gradle" ]]; then
    (cd "$dir" && "$GRADLE_HOME/bin/gradle" --quiet "$@")
  elif command -v gradle >/dev/null 2>&1; then
    (cd "$dir" && gradle --quiet "$@")
  else
    return 1
  fi
}

if ensure_gradle; then
  for i in "${!MOD_DIRS[@]}"; do
    MOD_DIR="$ROOT/Mods/${MOD_DIRS[$i]}"
    [[ -d "$MOD_DIR" ]] || continue
    echo "    building ${MOD_DIRS[$i]}…"
    # Generate the wrapper once so future builds use ./gradlew.
    if [[ ! -x "$MOD_DIR/gradlew" ]]; then
      if [[ -x "$GRADLE_HOME/bin/gradle" ]]; then
        (cd "$MOD_DIR" && "$GRADLE_HOME/bin/gradle" wrapper --gradle-version "$GRADLE_VERSION" --distribution-type bin) \
          || echo "warn: could not generate gradle wrapper for ${MOD_DIRS[$i]}"
      elif command -v gradle >/dev/null 2>&1; then
        (cd "$MOD_DIR" && gradle wrapper --gradle-version "$GRADLE_VERSION" --distribution-type bin) \
          || echo "warn: could not generate gradle wrapper for ${MOD_DIRS[$i]}"
      fi
      chmod +x "$MOD_DIR/gradlew" 2>/dev/null || true
    fi
    gradle_cmd "$MOD_DIR" build -x test || echo "warn: ${MOD_DIRS[$i]} build failed"
  done
else
  echo "warn: Gradle unavailable — skipping mod builds"
fi

# Bundle the freshly built jars, falling back to prebuilt ones.
mkdir -p "$RESOURCES_DIR/Mods"
for i in "${!MOD_JAR_NAMES[@]}"; do
  JAR_NAME="${MOD_JAR_NAMES[$i]}"
  MOD_DIR="$ROOT/Mods/${MOD_DIRS[$i]}"
  JAR="$(ls -t "$MOD_DIR"/build/libs/"$JAR_NAME"-*.jar 2>/dev/null | grep -v sources | head -1 || true)"
  [[ -z "$JAR" ]] && JAR="$MOD_DIR/build/libs/$JAR_NAME.jar"
  if [[ ! -f "$JAR" && -f "$ROOT/Resources/Mods/$JAR_NAME.jar" ]]; then
    JAR="$ROOT/Resources/Mods/$JAR_NAME.jar"
  fi
  if [[ -f "$JAR" ]]; then
    cp "$JAR" "$RESOURCES_DIR/Mods/$JAR_NAME.jar"
    echo "    bundled $JAR_NAME.jar"
  else
    echo "warn: no $JAR_NAME.jar produced — build skipped or failed (the launcher still works without it)"
  fi
done

echo "==> Signing app bundle (ad-hoc)"
xattr -cr "$APP" || true
# No --deep: the bundled NeoCraft Bedrock.app inside Resources keeps its own
# "SiliconBedrock Local" signature, which its account service requires.
codesign --force --sign - \
  --entitlements "$ROOT/entitlements.plist" \
  "$APP" >/dev/null
codesign --verify --deep --strict --verbose=1 "$APP"

echo
echo "Built $APP"
echo "Launch it with: open \"$APP\""
echo
echo "Note: NeoCraft downloads its own Eclipse Temurin JDK into"
echo "~/Library/Application Support/NeoCraft/runtime on first launch."

if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
