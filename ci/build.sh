#!/bin/bash
# Release build for the simulator (arm64 only, no signing). The scheme comes from the workspace listing.
set -eo pipefail
. ci/lib.sh
WS=$(ls -d ios/*.xcworkspace | head -1)
SCHEME=$(xcodebuild -workspace "$WS" -list -json | node -e '
  const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
  const s = (j.workspace.schemes || []).find((x) => !/^Pods|^Expo|^React|^EX|^RN|^hermes|^Yoga|^boost|^glog|^fmt|^Socket|^Sentry/.test(x));
  process.stdout.write(s || "");
')
[ -n "$SCHEME" ] || { echo "no app scheme"; exit 16; }
echo "workspace=$WS scheme=$SCHEME" | tee "$OUT/build-target.txt"
xcodebuild -workspace "$WS" -scheme "$SCHEME" -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO \
  build > "$OUT/xcodebuild.log" 2>&1 || { tail -80 "$OUT/xcodebuild.log"; exit 17; }
tail -5 "$OUT/xcodebuild.log"
gzip -f "$OUT/xcodebuild.log"
