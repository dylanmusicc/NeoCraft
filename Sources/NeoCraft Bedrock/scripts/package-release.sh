#!/bin/sh
# package-release.sh: the files of a release, in dist/, from a built app:
#
#   NeoCraftBedrock-<version>.zip                the app
#   NeoCraftBedrock-<version>-sources.tar.xz     the patched Wine, xgameruntime and Xodus trees the
#                                               engine was built from: with this repository at the
#                                               release's tag, the corresponding source of the app
#   SHA256SUMS                                  their checksums
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${SB_WORK:-/private/tmp/siliconbedrock-build}
VERSION=$(cat "$ROOT/VERSION")
DIST=$ROOT/dist
ZIP=NeoCraftBedrock-$VERSION.zip
SOURCES=NeoCraftBedrock-$VERSION-sources.tar.xz

[ -d "$DIST/NeoCraft Bedrock.app" ] || { printf 'package-release: no app; run scripts/build.sh\n' >&2; exit 1; }

printf '==> Writing %s\n' "$ZIP"
rm -f "$DIST/$ZIP" "$DIST/$SOURCES" "$DIST/SHA256SUMS"
# Extended attributes stay out: they aren't part of the app, and can name the builder's Mac.
ditto -c -k --norsrc --noextattr --keepParent "$DIST/NeoCraft Bedrock.app" "$DIST/$ZIP"

printf '==> Writing %s\n' "$SOURCES"
COPYFILE_DISABLE=1 tar -C "$WORK/engine/src" --exclude .git --uid 0 --gid 0 --uname '' --gname '' \
  -cJf "$DIST/$SOURCES" wine xgameruntime xodus

(cd "$DIST" && shasum -a 256 "$ZIP" "$SOURCES" > SHA256SUMS)
du -h "$DIST/$ZIP" "$DIST/$SOURCES" | sed "s#$DIST/##"
