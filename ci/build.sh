#!/bin/bash
# Release build for the simulator (arm64 only, no signing). The app scheme has the workspace name; the listing must hold it.
set -eo pipefail
. ci/lib.sh
WS=$(ls -d ios/*.xcworkspace | head -1)
SCHEME=$(basename "$WS" .xcworkspace)
xcodebuild -workspace "$WS" -list -json > "$OUT/schemes.json"
node -e 'process.exit(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).workspace.schemes.includes(process.argv[2])?0:1)' "$OUT/schemes.json" "$SCHEME" || SCHEME=""
[ -n "$SCHEME" ] || { echo "no app scheme"; exit 16; }
echo "workspace=$WS scheme=$SCHEME" | tee "$OUT/build-target.txt"
xcodebuild -workspace "$WS" -scheme "$SCHEME" -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO \
  build > "$OUT/xcodebuild.log" 2>&1 || { tail -80 "$OUT/xcodebuild.log"; exit 17; }
tail -5 "$OUT/xcodebuild.log"
gzip -f "$OUT/xcodebuild.log"
