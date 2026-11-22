#!/bin/bash




set -euo pipefail

STEP="${1:-}"
fail() { echo "GATE $STEP FAIL: $*"; exit 1; }
case "$STEP" in
toolchain)
  CF="${CM_FILE_ENV:-}"; [ -n "$CF" ] || fail "CM_FILE_ENV not set"
  sw_vers || true
  XV=$(xcodebuild -version | { grep -E '^Xcode [0-9]' || true; }) || fail "no xcodebuild"; echo "$XV"
  [ "$(printf '%s\n' "$XV" | grep -c .)" = 1 ] || fail "not exactly one Xcode version line"
  [[ "$XV" == "Xcode 26.6"* ]] || fail "Xcode is not 26.6 (run 3 and B's pins)"
  NV=$(node -v); echo "node $NV"; [ "$NV" = "v24.17.0" ] || fail "node is not v24.17.0 (yaml pin)"
  PV=$(pod --version) || fail "no pod"; echo "pod $PV"; [ "$PV" = "1.16.2" ] || fail "pod is not 1.16.2 (yaml pin)"
  JV=$(java -version 2>&1 || true); printf '%s\n' "$JV" | sed -n 1,3p
  [[ "$JV" == *'version "17.'* ]] || fail "java is not 17 (Codemagic default 17.0.19)"

  xcrun simctl list devices available -j > out/sims.json || fail "simctl list failed"
  node .maestro/cm-pick.js < out/sims.json > out/sims.env || fail "no single available iPhone 17 Pro on iOS 26.5"
  cat out/sims.env
  grep -E "^(SIM_RUNTIME|IPHONE_UDID)=" out/sims.env >> "$CF"
  PG=$(sysctl -n hw.pagesize); TOTAL=$(sysctl -n hw.memsize)
  FREEP=$(vm_stat | awk '/Pages free|Pages inactive|Pages speculative/ {gsub("\\.","",$NF); s+=$NF} END {print s+0}')
  echo "memory total_mb=$(( TOTAL / 1048576 )) free_mb=$(( FREEP * PG / 1048576 )) (record only)"
  ;;
bundle)

  [ -n "${APP_PATH:-}" ] && [ -d "$APP_PATH" ] || fail "no .app (APP_PATH=${APP_PATH:-unset})"
  B="$APP_PATH/main.jsbundle"
  [ -s "$B" ] || fail "no main.jsbundle"
  ls -la "$B"
  MAGIC=$(head -c 4 "$B" | od -An -tx1 | tr -d ' \n')
  echo "magic=$MAGIC"
  [ "$MAGIC" = "c61fbc03" ] || fail "main.jsbundle is not Hermes bytecode"
  c() { { grep -a -o -F "$1" "$B" || true; } | wc -l | tr -d ' '; }
  PC=$(c ap-northeast-1); echo "positive-control ap-northeast-1=$PC"; [ "$PC" -ge 1 ] || fail "positive control 0 (count method broken)"



  VF="${CM_VALUES_FILE:-.maestro/cm-values.txt}"
  [ -s "$VF" ] || fail "values file $VF missing or empty"
  ONES=$(mktemp); N1=0; N0=0; P=0; LN=0
  while read -r k v || [ -n "${k:-}" ]; do
    LN=$((LN+1)); case "$k" in ''|'#'*) continue;; esac
    [ -n "${v:-}" ] && [[ "$v" != *" "* ]] || fail "values file line $LN: not '<1|0|0re> <one word>'"
    case "$k" in
      1) printf '%s
' "$v" >> "$ONES"; N1=$((N1+1)) ;;
      0|0re) N0=$((N0+1)) ;;
      *) fail "values file line $LN: kind '$k' is not 1, 0 or 0re" ;;
    esac
  done < "$VF"
  [ "$N1" -ge 1 ] && [ "$N0" -ge 1 ] || fail "values file needs at least one '1' line and one '0'/'0re' line (1=$N1 0=$N0)"
  while read -r k v || [ -n "${k:-}" ]; do
    case "$k" in
      1) n=$(c "$v"); echo "want1 $v=$n"; [ "$n" -eq 1 ] || fail "$v count $n, expected 1" ;;
      0) n=$(c "$v"); echo "want0 $v=$n"; P=$((P+n)) ;;
      0re) n=$( { grep -a -o -E "$v" "$B" || true; } | { grep -v -x -F -f "$ONES" || true; } | wc -l | tr -d ' '); echo "want0re $v=$n"; P=$((P+n)) ;;
    esac
  done < "$VF"
  rm -f "$ONES"
  echo "zero-total=$P"; [ "$P" -eq 0 ] || fail "values that must be 0 were found"
  ;;
*) fail "unknown step" ;;
esac
echo "GATE $STEP ok"
