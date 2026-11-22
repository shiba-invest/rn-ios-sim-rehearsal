#!/bin/bash
set -uo pipefail
UDID="$1"; L="$2"; O="$3"
OUT="$PWD/out/$L"; mkdir -p "$OUT"
RAW="$HOME/cm-maestro-raw/$L"; mkdir -p "$RAW/shots"
NET="$OUT/net.txt"
. "$(dirname "$0")/cm-lim.sh"
T0=$(date +%s)
REC=""; NETERR=0; ENTER_AT=0
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
  find "$RAW" -name "*.png" -exec cp {} "$OUT/" \; 2>/dev/null || true
  limf 20 xcrun simctl io "$UDID" screenshot "$OUT/99-final.png" >/dev/null 2>&1 || true
  if [ -f "$OUT/raw.mp4" ]; then
    { limf 60 avconvert --preset Preset960x540 --source "$OUT/raw.mp4" --output "$OUT/$L.mp4" >/dev/null 2>&1 && mv "$OUT/raw.mp4" "$RAW/raw.mp4"; } || true
  fi
  limf 30 xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  echo "$L rc=$RC network-errors=$NETERR seconds=$(( $(date +%s) - T0 ))" | tee -a "$OUT/result.txt"
  exit $RC
}
trap finish EXIT
say "boot"
lim 60 xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
lim 480 xcrun simctl bootstatus "$UDID" -b >/dev/null || { note "GATE boot: not booted (rc 142 = over the limit)"; exit 1; }
lim 60 xcrun simctl install "$UDID" "$APP_PATH" || { note "GATE install: failed (rc 142 = over the limit)"; exit 1; }
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/raw.mp4" >/dev/null 2>&1 &
REC=$!
sleep 2
mt() {
  local n="$1" f="$2"; shift 2; local r=0
  lim "${MT_LIMIT:-300}" maestro --device "$UDID" test --test-output-dir "$RAW/m-$n" -e ORIENT="$O" "$@" ".maestro/$f" > "$RAW/m-$n.console" 2>&1 || r=$?
  note "flow $n rc=$r (142 = over the limit) at $(date -u +%H:%M:%S)"
  return "$r"
}
shots() {
  local t0 t; t0=$(date +%s)
  for t in 3 15 40 70; do
    while [ $(( $(date +%s) - t0 )) -lt "$t" ]; do sleep 1; done
    limf 30 xcrun simctl io "$UDID" screenshot "$RAW/shots/login-$1-t$(printf %02d "$t").png" >/dev/null 2>&1 || true
  done
}
home() {
  local r=0 sp; ENTER_AT=$(date +%s)
  shots "$1" & sp=$!
  MT_LIMIT=120 mt "home-$1" trial-home.yaml || r=$?
  kill "$sp" 2>/dev/null || true; wait "$sp" 2>/dev/null || true
  note "login $1 enter-to-result-s=$(( $(date +%s) - ENTER_AT )) home=$([ "$r" -eq 0 ] && echo yes || echo no)"
  return "$r"
}
login_net_msg() {
  local h; h=$(lim 60 maestro --device "$UDID" hierarchy 2>/dev/null) || return 1
  case "$h" in *"ログインできませんでした。通信環境をご確認ください"*) return 0;; *) return 1;; esac
}
flow_fail() { note "flow failed ($1)"; lim 30 bash .maestro/netcheck.sh "$NET" "after-fail" >/dev/null 2>&1 || true; exit 1; }
fault_hook() { [ -n "${FAULT_HOOK:-}" ] && bash "$FAULT_HOOK" "$1" "$UDID"; return 0; }
fault_hook pre-login
lim 30 bash .maestro/netcheck.sh "$NET" "pre-login" >/dev/null 2>&1 || true
mt login trial-login.yaml -e LOGIN_ID="$LOGIN_ID" -e LOGIN_PW="$LOGIN_PW" || flow_fail "login form, before the Enter key"
fault_hook post-enter
if ! home first; then
  if login_net_msg; then
    NETERR=1; note "login network message after the first Enter (network-errors=1)"
    limf 30 xcrun simctl io "$UDID" screenshot "$RAW/shots/login-net-first.png" >/dev/null 2>&1 || true
    lim 30 bash .maestro/netcheck.sh "$NET" "net-msg-first" >/dev/null 2>&1 || true
    lim 40 sleep 30 || true
    fault_hook pre-retry
    MT_LIMIT=300 mt retry trial-retry.yaml || flow_fail "resubmit could not press the login button"
    home retry || flow_fail "after the resubmit (network-errors=1, stopped at once)"
  else
    flow_fail "after the first Enter, no login network message on screen"
  fi
fi
say "flow passed"
exit 0
