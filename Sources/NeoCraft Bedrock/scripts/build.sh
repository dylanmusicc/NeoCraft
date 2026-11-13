#!/bin/sh
# build.sh: build everything from source, into dist/: NeoCraft Bedrock.app and the release files.
#
# Needs an Apple Silicon Mac with macOS 27, the Command Line Tools and Homebrew; the engine's
# bootstrap.sh installs the rest. Downloads Wine, xgameruntime and Xodus at their pinned commits.
#
# Environment:
#   SB_WORK           where the builds go, by default /private/tmp/siliconbedrock-build. Keep it out of
#                     the home folder and free of spaces: binaries record paths under it.
#   JOBS              parallel jobs, by default one per CPU core
#   SIGNING_IDENTITY  what signs the app, by default the identity signing-identity.sh creates
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export SB_WORK=${SB_WORK:-/private/tmp/siliconbedrock-build}
export ENGINE_WORK=$SB_WORK/engine
export JOBS=${JOBS:-$(sysctl -n hw.ncpu)}
export SOURCE_REVISION=${SOURCE_REVISION:-v$(cat "$ROOT/VERSION")}

case $SB_WORK in
  "$HOME"/*) printf 'build: SB_WORK must be outside the home folder\n' >&2; exit 1 ;;
  *' '*) printf 'build: SB_WORK must have no spaces\n' >&2; exit 1 ;;
esac
mkdir -p "$ENGINE_WORK"

"$ROOT/scripts/signing-identity.sh"
"$ROOT/engine/packaging/macos/bootstrap.sh"
"$ROOT/engine/packaging/macos/build.sh"
"$ROOT/engine/packaging/macos/package.sh" --dev
"$ROOT/engine/tests/bundle/check.sh"
"$ROOT/scripts/build-app.sh"
"$ROOT/scripts/package-release.sh"
"$ROOT/scripts/check-clean.sh"
