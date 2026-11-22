#!/bin/bash
# Secret sweep over everything in OUT before upload. A file that holds the practice password, the planted marker,
# a pool id other than the made-up one, or an API host is moved to WITHHELD (never uploaded).
# Only counts are written, never the values. Images and video are searched as bytes; pixels are not read.
set -eo pipefail
. ci/lib.sh
R="$OUT/sweep.txt"
: > "$R"
total=0; held=0
while IFS= read -r -d '' f; do
  rel="${f#$OUT/}"
  [ "$rel" = sweep.txt ] && continue
  total=$((total + 1))
  pw=$(LC_ALL=C grep -a -c -F -- "$LOGIN_PW" "$f" || true)
  mk=$(LC_ALL=C grep -a -c -F -- "$PLANT_MARKER" "$f" || true)
  pool=$( (LC_ALL=C grep -a -o -E '[a-z]{2}-[a-z]+-[0-9]_[A-Za-z0-9]{9}' "$f" || true) | (grep -v -c '_FAKEPOOL0$' || true) )
  api=$( (LC_ALL=C grep -a -o -E '[a-z0-9]{10}\.execute-api\.' "$f" || true) | wc -l | tr -d ' ')
  if [ "$pw" -gt 0 ] || [ "$mk" -gt 0 ] || [ "$pool" -gt 0 ] || [ "$api" -gt 0 ]; then
    mkdir -p "$WITHHELD/$(dirname "$rel")"
    mv "$f" "$WITHHELD/$rel"
    held=$((held + 1))
    echo "withheld $rel pw=$pw marker=$mk pool=$pool api=$api" >> "$R"
  fi
done < <(find "$OUT" -type f -print0)
echo "sweep files=$total withheld=$held" >> "$R"
cat "$R"
