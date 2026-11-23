#!/bin/bash

















set -uo pipefail
UDID="$1"; L="$2"; O="$3"
OUT="$PWD/out/$L"; mkdir -p "$OUT"
RAW="$HOME/cm-maestro-raw/$L"; mkdir -p "$RAW/shots"
NET="$OUT/net.txt"
. "$(dirname "$0")/cm-lim.sh"
T0=$(date +%s)
REC=""; NETERR=0; ENTER_AT=0; HOME_OK=0
APP="${APP_PATH:-}"; LID="${LOGIN_ID:-}"; LPW="${LOGIN_PW:-}"
say() { echo "[$L $(( $(date +%s) - T0 ))s] $*"; }
note() { say "$*"; echo "$*" >> "$OUT/result.txt"; }
: > "$OUT/result.txt"
if [ "$(cm_left)" -le 0 ]; then note "DEADLINE: second $CM_DEADLINE_SEC passed, $L not started"; exit 1; fi

finish() {
  RC=$?; trap - EXIT

  if [ -n "$REC" ]; then
    kill -INT "$REC" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$REC" 2>/dev/null || break; sleep 1; done
    kill -KILL "$REC" 2>/dev/null || true; wait "$REC" 2>/dev/null || true
  fi



  find "$RAW" -name "*.png" ! -path "*/shots/*" ! -path "*/m-login/*" ! -path "*/m-retry/*" ! -path "*/m-home-*" -exec cp {} "$OUT/" \; 2>/dev/null || true
  echo "login-shots-kept-outside=$(find "$RAW" -name "*.png" \( -path "*/shots/*" -o -path "*/m-login/*" -o -path "*/m-retry/*" -o -path "*/m-home-*" \) 2>/dev/null | wc -l | tr -d ' ')" >> "$OUT/result.txt"
  if [ "$HOME_OK" = 1 ]; then limf 20 xcrun simctl io "$UDID" screenshot "$OUT/99-final.png" >/dev/null 2>&1 || true
  else echo "99-final not taken: the home was not reached (the login screen may show the ID)" >> "$OUT/result.txt"; fi
  if [ -f "$OUT/raw.mp4" ]; then
    { limf 60 avconvert --preset Preset960x540 --source "$OUT/raw.mp4" --output "$OUT/$L.mp4" >/dev/null 2>&1 && mv "$OUT/raw.mp4" "$RAW/raw.mp4"; } || true
  fi
  limf 30 xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  echo "$L rc=$RC network-errors=$NETERR seconds=$(( $(date +%s) - T0 ))" | tee -a "$OUT/result.txt"
  if [ "$RC" = 0 ]; then echo "$L-result=ok" >> "$OUT/result.txt"; fi
  exit $RC
}
trap finish EXIT

say "boot"
lim 140 xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
lim 1310 xcrun simctl bootstatus "$UDID" -b >/dev/null || { r=$?; note "GATE boot: not booted (rc $r; 142 = over the limit)"; exit 1; }
[ -n "$APP" ] && [ -d "$APP" ] || { note "GATE install: no .app (APP_PATH unset or not a folder)"; exit 1; }
lim 300 xcrun simctl install "$UDID" "$APP" || { r=$?; note "GATE install: failed (rc $r; 142 = over the limit)"; exit 1; }

start_rec() { [ -z "$REC" ] || return 0
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/raw.mp4" >/dev/null 2>&1 &
  REC=$!; sleep 2; }

mt() { # <name> <flow> [-e ...]: one maestro test, debug output outside out/; returns its rc
  local n="$1" f="$2"; shift 2; local r=0
  lim "${MT_LIMIT:-300}" maestro --device "$UDID" test --test-output-dir "$RAW/m-$n" -e ORIENT="$O" "$@" ".maestro/$f" > "$RAW/m-$n.console" 2>&1 < /dev/null || r=$?
  note "flow $n rc=$r (142 = over the limit) at $(date -u +%H:%M:%S)"
  return "$r"
}
shots() { # D3 <tag>
  local t0 t; t0=$(date +%s)
  for t in 3 15 40 70; do
    while [ $(( $(date +%s) - t0 )) -lt "$t" ]; do sleep 1; done
    limf 85 xcrun simctl io "$UDID" screenshot "$RAW/shots/login-$1-t$(printf %02d "$t").png" >/dev/null 2>&1 || true
  done
}
home() { # <tag>: trial-home after one Enter with the D3 shots beside it; records the seconds from the Enter to the home
  local r=0 sp; ENTER_AT=$(date +%s)
  shots "$1" & sp=$!
  MT_LIMIT=610 mt "home-$1" trial-home.yaml || r=$?
  kill "$sp" 2>/dev/null || true; wait "$sp" 2>/dev/null || true
  note "login $1 enter-to-result-s(with the Maestro CLI start)=$(( $(date +%s) - ENTER_AT )) home=$([ "$r" -eq 0 ] && echo yes || echo no)"
  return "$r"
}
login_net_msg() { # 0 when a non-credential login failure is on screen (a1a.tsx:83 network, :84 general). The tree is searched, never saved.
  local h; h=$(lim 200 maestro --device "$UDID" hierarchy 2>/dev/null) || return 1
  case "$h" in *"ログインできませんでした。通信環境をご確認ください"*|*"ログインできませんでした。もう一度お試しください"*) return 0;; *) return 1;; esac
}
flow_fail() { note "flow failed ($1)"; lim 115 bash .maestro/netcheck.sh "$NET" "after-fail" >/dev/null 2>&1 || true; exit 1; }
fault_hook() { local fh="${FAULT_HOOK:-}"; [ -n "$fh" ] || return 0; bash "$fh" "$1" "$UDID" || true; }
FLOWS=.maestro/cm-flows.txt
[ -f "$FLOWS" ] || { note "GATE flows: $FLOWS missing"; exit 1; }

fault_hook pre-login
lim 115 bash .maestro/netcheck.sh "$NET" "pre-login" >/dev/null 2>&1 || true
MT_LIMIT=1180 mt login trial-login.yaml -e LOGIN_ID="$LID" -e LOGIN_PW="$LPW" || flow_fail "login form, before the Enter key"
fault_hook post-enter
if ! home first; then
  if login_net_msg; then
    NETERR=1; note "login network message after the first Enter (network-errors=1)"
    limf 30 xcrun simctl io "$UDID" screenshot "$RAW/shots/login-net-first.png" >/dev/null 2>&1 || true
    lim 115 bash .maestro/netcheck.sh "$NET" "net-msg-first" >/dev/null 2>&1 || true
    lim 40 sleep 30 || true
    fault_hook pre-retry
    MT_LIMIT=300 mt retry trial-retry.yaml || flow_fail "resubmit could not press the login button"
    home retry || flow_fail "after the resubmit (network-errors=1, stopped at once)"
  else
    flow_fail "after the first Enter, no login network message on screen"
  fi
fi
HOME_OK=1; start_rec
while read -r n f m <&3 || [ -n "${n:-}" ]; do
  case "$n" in ''|'#'*) continue;; esac
  [ -n "${f:-}" ] && [ -n "${m:-}" ] || { note "GATE flows: bad line in $FLOWS"; exit 1; }
  MT_LIMIT=460 mt "$n" "$f" || { if [ -n "$(find "$RAW/m-$n" -name "05-no-record-7-months*.png" -print 2>/dev/null)" ]; then
      note "GATE data FAIL: $n no photo record in 7 months on the home the app opened (fresh simulator = first assigned home)"; fi
    flow_fail "$m"; }
done 3< "$FLOWS"
say "flow passed"
exit 0
