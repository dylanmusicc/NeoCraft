#!/bin/sh
# check-clean.sh: refuse a tree or a release that names the builder: the login name, the full name or
# the home folder, in any file of the repository, in the app, or in the engine inside it.
#
# EXTRA_PRIVATE_WORDS adds words to look for, separated by spaces, such as an email address.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${SB_WORK:-/private/tmp/siliconbedrock-build}
ENGINE_VERSION=$(cat "$ROOT/engine/VERSION")
BUNDLE=$WORK/engine/packages/macrock-engine-$ENGINE_VERSION.bundle
USER_NAME=$(id -un)
FULL_NAME=$(id -F 2>/dev/null || true)

found=0
scan() {
  label=$1
  shift
  # shellcheck disable=SC2086
  hits=$(grep -rlaF -e "$USER_NAME" -e "$HOME" ${FULL_NAME:+-e "$FULL_NAME"} \
    $(for word in ${EXTRA_PRIVATE_WORDS:-}; do printf -- '-e %s ' "$word"; done) \
    --exclude-dir=.build --exclude-dir=dist --exclude-dir=Vendor "$@" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    found=1
    printf 'check-clean: %s names the builder:\n%s\n' "$label" "$hits" >&2
  else
    printf 'check-clean: %s is clean\n' "$label"
  fi
}

scan "the repository" "$ROOT"
[ ! -d "$ROOT/dist/NeoCraft Bedrock.app" ] || scan "the app" "$ROOT/dist/NeoCraft Bedrock.app"
[ ! -d "$BUNDLE" ] || scan "the engine" "$BUNDLE"
[ "$found" = 0 ] || exit 1
