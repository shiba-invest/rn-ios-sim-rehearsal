#!/bin/bash

set -u
UDID="$1"; L="$2"; O="$3"
OUT="$PWD/out/$L"; mkdir -p "$OUT"
T0=$(date +%s)
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/raw.mp4" &
REC=$!
sleep 2
maestro --device "$UDID" test --test-output-dir "$OUT/m" -e ORIENT="$O" -e LOGIN_ID="$LOGIN_ID" -e LOGIN_PW="$LOGIN_PW" .maestro/trial-flow.yaml
RC=$?

if [ "$RC" -ne 0 ]; then
  maestro --device "$UDID" hierarchy > "$OUT/hierarchy.json" 2>/dev/null || true
  if grep -qF -- "$LOGIN_PW" "$OUT/hierarchy.json"; then rm -f "$OUT/hierarchy.json"; echo "hierarchy dropped (held input)"; fi
fi

find "$OUT/m" -name "*.png" -exec cp {} "$OUT/" \;
ls -la "$OUT"
rm -rf "$OUT/m"
xcrun simctl io "$UDID" screenshot "$OUT/99-final.png" || true
kill -INT $REC; wait $REC || true

avconvert --preset Preset960x540 --source "$OUT/raw.mp4" --output "$OUT/$L.mp4" && rm -f "$OUT/raw.mp4" || true
xcrun simctl shutdown "$UDID" || true
echo "$L rc=$RC seconds=$(( $(date +%s) - T0 ))" | tee "$OUT/result.txt"
exit $RC
