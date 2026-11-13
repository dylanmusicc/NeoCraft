#!/bin/sh
# test.sh: run the launcher's tests. The Command Line Tools have Swift Testing, in folders swift test
# only looks in under Xcode, so this names them. Arguments go to swift test, such as --filter NAME.
#
# Environment: SB_WORK (where builds go, see build.sh).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${SB_WORK:-/private/tmp/siliconbedrock-build}
TOOLS=$(xcode-select -p)

case $TOOLS in
  */CommandLineTools) ;;
  *) exec swift test --package-path "$ROOT/LauncherCore" --scratch-path "$WORK/core-tests" "$@" ;;
esac

exec swift test --package-path "$ROOT/LauncherCore" --scratch-path "$WORK/core-tests" \
  -Xswiftc -plugin-path -Xswiftc "$TOOLS/usr/lib/swift/host/plugins/testing" \
  -Xswiftc -F -Xswiftc "$TOOLS/Library/Developer/Frameworks" \
  -Xlinker -F -Xlinker "$TOOLS/Library/Developer/Frameworks" \
  -Xlinker -rpath -Xlinker "$TOOLS/Library/Developer/Frameworks" \
  -Xlinker -rpath -Xlinker "$TOOLS/Library/Developer/usr/lib" "$@"
