#!/bin/bash
# Gate b: the built app holds a Hermes bundle, the made-up pool id is inside (positive control),
# and no other pool id or API host is inside (generic patterns; the public repo lists no real id).
set -eo pipefail
. ci/lib.sh
R="$OUT/gate-b.txt"
: > "$R"
fail() { echo "GATE-B FAIL: $*" | tee -a "$R"; exit 13; }
APP=$(ls -d build/Build/Products/Release-iphonesimulator/*.app | head -1)
[ -d "$APP" ] || fail "no .app"
echo "$APP" > "$OUT/app-path.txt"
B="$APP/main.jsbundle"
[ -f "$B" ] || fail "no main.jsbundle"
magic=$(head -c 8 "$B" | xxd -p)
echo "bundle bytes=$(wc -c < "$B") magic=$magic" | tee -a "$R"
[ "$magic" = "c61fbc03c103191f" ] || fail "not Hermes bytecode"
pos=$(LC_ALL=C grep -c -a 'ap-northeast-1_FAKEPOOL0' "$B" || true)
echo "positive-control made-up-pool count=$pos" | tee -a "$R"
[ "$pos" -ge 1 ] || fail "positive control not found (the count method is broken)"
other=$( (LC_ALL=C grep -a -o -E '[a-z]{2}-[a-z]+-[0-9]_[A-Za-z0-9]{9}' "$B" || true) | (grep -v -c '_FAKEPOOL0$' || true) )
api=$( (LC_ALL=C grep -a -o -E '[a-z0-9]{10}\.execute-api\.' "$B" || true) | wc -l | tr -d ' ')
echo "other-pool-id count=$other api-host count=$api" | tee -a "$R"
[ "$other" -eq 0 ] && [ "$api" -eq 0 ] || fail "another id inside the bundle"
echo "GATE-B OK" | tee -a "$R"
