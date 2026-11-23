#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${DERIVED:-/tmp/nail-derived}"
OUT_APP="$ROOT/build/Meet Nail.app"
STALE_APP="$ROOT/build/NAIL.app"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export CLANG_MODULE_CACHE_PATH="/tmp/clang-module-cache"

xcodebuild \
  -project "$ROOT/NAIL.xcodeproj" \
  -scheme NAIL \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS="-disable-sandbox" \
  build

BUILT_APP="$DERIVED/Build/Products/Release/Meet Nail.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "Missing built app at $BUILT_APP" >&2
  exit 1
fi

mkdir -p "$ROOT/build"
find "$ROOT/build" -maxdepth 1 -name "*.app" -exec rm -rf {} +
cp -cR "$BUILT_APP" "$OUT_APP"
rm -rf "$BUILT_APP" "$HOME/Library/Developer/Xcode/DerivedData"/NAIL-* /tmp/nail-*/Build/Products/*/*.app /tmp/meetnail-*/Build/Products/*/*.app 2>/dev/null || true

if [ ! -x "$OUT_APP/Contents/Frameworks/Electron.app/Contents/MacOS/Electron" ]; then
  echo "Missing embedded Electron runtime in $OUT_APP" >&2
  exit 1
fi

codesign --force --sign - "$OUT_APP"
codesign --verify --strict "$OUT_APP"
echo "Built and signed: $OUT_APP"
