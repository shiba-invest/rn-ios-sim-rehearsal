#!/bin/bash

















set -uo pipefail
UDID="$1"; L="$2"; O="$3"
OUT="$PWD/out/$L"; mkdir -p "$OUT"
RAW="$HOME/cm-maestro-raw/$L"; mkdir -p "$RAW/shots"
NET="$OUT/net.txt"
. "$(dirname "$0")/cm-lim.sh"
T0=$(date +%s)
REC=""; NETERR=0; ENTER_AT=0; HOME_OK=0; RESC=0
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
  if [ "$HOME_OK" = 1 ]; then limf 115 xcrun simctl io "$UDID" screenshot "$OUT/99-final.png" >/dev/null 2>&1 || true
  else echo "99-final not taken: the home was not reached (the login screen may show the ID)" >> "$OUT/result.txt"; fi
  if [ -f "$OUT/raw.mp4" ]; then
    { limf 60 avconvert --preset Preset960x540 --source "$OUT/raw.mp4" --output "$OUT/$L.mp4" >/dev/null 2>&1 && mv "$OUT/raw.mp4" "$RAW/raw.mp4"; } || true
  fi
  limf 30 xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  echo "$L rc=$RC network-errors=$NETERR rescued=${RESC:-0} seconds=$(( $(date +%s) - T0 ))" | tee -a "$OUT/result.txt"
  if [ "$RC" = 0 ]; then echo "$L-result=ok" >> "$OUT/result.txt"; fi
  exit $RC
}
trap finish EXIT

say "boot"
lim 140 xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
lim 1310 xcrun simctl bootstatus "$UDID" -b >/dev/null || { r=$?; note "GATE boot: not booted (rc $r; 142 = over the limit)"; exit 1; }
[ -n "$APP" ] && [ -d "$APP" ] || { note "GATE install: no .app (APP_PATH unset or not a folder)"; exit 1; }
lim 390 xcrun simctl install "$UDID" "$APP" || { r=$?; note "GATE install: failed (rc $r; 142 = over the limit)"; exit 1; }

start_rec() { [ -z "$REC" ] || return 0
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/raw.mp4" >/dev/null 2>&1 &
  REC=$!; sleep 2; }; drv_watch() { local c="$RAW/m-$1.console" p="$RAW/m-$1.pid" a; while sleep 5; do [ -f "$c" ] || continue; a=$(perl -ne 's/\r//g; s/\e\[[0-9;]*[A-Za-z]//g; if (/\.\.\. ?(?:COMPLETED|FAILED|SKIPPED|WARNED)?\s*$/) { $s = 1; last } $a = $1 if !$a && /^([0-9]{9,11}) .*\b[A-Za-z]{2,40}(?:Exception|Error|Timeout|Failure|Unreachable)\b/; END { print $s ? "step" : ($a || "") }' "$c" 2>/dev/null) || a=""; case "$a" in step) return 0;; '') continue;; esac; [ $(( $(date +%s) - a )) -ge "$STALL_S" ] || continue; note "driver flow $1 stall: printed an error class line and ran no step for $STALL_S s (cm-limits.txt driver-stall-s): cut now, not at its limit"; [ ! -s "$p" ] || kill -TERM -- "-$(cat "$p")" 2>/dev/null || true; return 0; done; }

mt() { # <name> <flow> [-e ...]: one maestro test, debug output outside out/; returns its rc
  local n="$1" f="$2"; shift 2; local r=0 wp="" L=$(( ${MT_LIMIT:-300} - 300 + DS )); [ -z "${STALL_S:-}" ] || { drv_watch "$n" & wp=$!; }
  CM_PIDF="$RAW/m-$n.pid" lim "$L" maestro --device "$UDID" test --test-output-dir "$RAW/m-$n" -e ORIENT="$O" "$@" ".maestro/$f" > >(perl -ne 'BEGIN{$|=1} print time()." ".$_' > "$RAW/m-$n.console") 2>&1 < /dev/null || r=$?
  [ -z "$wp" ] || { kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null; } || true; note "flow $n rc=$r (142 = over the limit) at $(date -u +%H:%M:%S)"; local SR=""; [ "$r" = 0 ] || SR=$(lim 30 node .maestro/cm-steps.js "$RAW/m-$n.console" "$n" "$(date +%s)" 2>/dev/null) || true; [ -z "$SR" ] || while IFS= read -r x; do note "$x"; done <<< "$SR"; [ "$r" = 0 ] || { local SC; SC=$(lim 95 bash .maestro/cm-screen.sh "$UDID" 2>/dev/null) || SC="screen: check did not finish"; note "driver flow $n $SC"; }
  case "$SR" in *" zero-step: "*) [ -z "${MT_AGAIN:-}" ] || { note "GATE driver FAIL: flow ${n%-again} ran no step twice (rc $MT_AGAIN then $r, the clean-up between; Maestro ended before its first step both times: the driver did not start)"; exit 1; }; [ "$(cm_left)" -ge "$L" ] || { note "flow $n: no step ran (rc $r); $(cm_left) s left < this flow's limit $L s: no clean-up, no retake"; return "$r"; }; local CL CR=0; CL=$(lim 70 bash .maestro/cm-driver.sh "$UDID" 2>/dev/null) || CR=$?; [ -z "$CL" ] || while IFS= read -r x; do note "${x/#driver /driver flow $n }"; done <<< "$CL"; [ "$CR" != 3 ] || { note "GATE driver FAIL: flow $n ran no step and port 22087 still has a listener after the clean-up (no retake)"; exit 1; }; [ "$CR" != 142 ] || note "driver clean-up cut at its limit (70 s)"; note "flow $n: no step ran (rc $r), the same flow once more after the clean-up (nothing on the app was pressed)"; MT_AGAIN=$r mt "$n-again" "$f" "$@"; r=$?; [ "$r" != 0 ] || { RESC=$((RESC + 1)); note "RESCUED flow $n: passed on its -again after the driver clean-up (counted apart from a clean pass)"; };; *" stalled-step: "*" inputText RUNNING "*|*" stalled-step: "*" eraseText RUNNING "*) case "$n" in login|login-again) note "GATE input FAIL: flow $n: an input step stayed RUNNING to the end (steps ran, so the driver was up; not driver / screen / net; no retake: the commander decides after B plist 5 with / 5 without)"; exit 1;; esac;; esac; return "$r"
}
shots() { # D3 <tag>
  local t0 t; t0=$(date +%s)
  for t in 3 15 40 70; do
    while [ $(( $(date +%s) - t0 )) -lt "$t" ]; do sleep 1; done
    limf 115 xcrun simctl io "$UDID" screenshot "$RAW/shots/login-$1-t$(printf %02d "$t").png" >/dev/null 2>&1 || true
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
  local h="" r=0 k; for k in 1 2; do r=0; h=$(lim 200 maestro --device "$UDID" hierarchy 2>/dev/null) || r=$?; [ "$r" = 142 ] || break; note "screen check: maestro hierarchy over its limit (rc 142, try $k of 2)"; done; [ "$r" != 142 ] || return 2; [ "$r" = 0 ] || { HRC=$r; return 6; }
  case "$h" in *"ログインできませんでした。通信環境をご確認ください"*|*"ログインできませんでした。もう一度お試しください"*) return 0;; *"このアプリのことについて"*) return 3;; *"仮のパスワードでログインしました"*) return 4;; *"新しい版が出ていま"*) return 5;; *"ホーム"*) return 7;; *) return 1;; esac
}
flow_fail() { note "flow failed ($1)"; lim 115 bash .maestro/netcheck.sh "$NET" "after-fail" >/dev/null 2>&1 || true; exit 1; }
fault_hook() { local fh="${FAULT_HOOK:-}"; [ -n "$fh" ] || return 0; bash "$fh" "$1" "$UDID" || true; }
FLOWS=.maestro/cm-flows.txt; DS=$(cm_tab driver-start-s); STALL_S=$(cm_tab driver-stall-s); [ -n "$DS" ] || { note "GATE driver FAIL: driver-start-s is not filled in .maestro/cm-limits.txt"; exit 1; }; export MAESTRO_DRIVER_STARTUP_TIMEOUT=$(( DS * 1000 ))
[ -f "$FLOWS" ] || { note "GATE flows: $FLOWS missing"; exit 1; }

fault_hook pre-login
NW0=$(date +%s); NW=$(lim 600 bash .maestro/cm-netwait.sh "$NET" "pre-login" 2>/dev/null) || { r=$?; if [ "$r" = 3 ]; then note "GATE net FAIL: no http code from the check; the login was not tried"; else note "GATE net FAIL: network not reachable before the login for $(( $(date +%s) - NW0 )) s ($(grep -c ' pre-login-' "$NET" 2>/dev/null) tries, rc $r; 142 = over the limit); the login was not tried"; fi; exit 1; }; note "$NW"
MT_LIMIT=1260 mt login trial-login.yaml -e LOGIN_ID="$LID" -e LOGIN_PW="$LPW" || flow_fail "login form, before the Enter key"
fault_hook post-enter
if ! home first; then
  LNM=0; login_net_msg || LNM=$?; [ "$LNM" != 2 ] || { note "GATE screen FAIL: hierarchy timed out twice"; exit 1; }; case "$LNM" in 3) note "GATE account FAIL: consent screen after the login (this pair has not agreed to the latest version)"; exit 1;; 4) note "GATE account FAIL: new password screen after the login (temporary password not changed)"; exit 1;; 5) note "GATE screen FAIL: version notice over the home after the login"; exit 1;; 6) note "GATE screen FAIL: maestro hierarchy failed (rc ${HRC:-?}); the screen after the login is not known"; exit 1;; 7) note "GATE screen FAIL: the home is on screen (ホーム), but the home flow failed (see its failed-step line)"; exit 1;; esac; if [ "$LNM" = 0 ]; then
    NETERR=1; note "login network message after the first Enter (network-errors=1)"
    limf 115 xcrun simctl io "$UDID" screenshot "$RAW/shots/login-net-first.png" >/dev/null 2>&1 || true
    lim 115 bash .maestro/netcheck.sh "$NET" "net-msg-first" >/dev/null 2>&1 || true
    lim 90 sleep 30 || true
    fault_hook pre-retry
    MT_LIMIT=400 mt retry trial-retry.yaml || flow_fail "resubmit could not press the login button"
    home retry || flow_fail "after the resubmit (network-errors=1, stopped at once)"; RESC=$((RESC + 1)); note "RESCUED flow login: home after the resubmit (network-errors=1; counted apart from a clean pass)"
  else
    flow_fail "after the first Enter: no home, no login network message, no consent / new password / version notice on screen"
  fi
fi
HOME_OK=1; start_rec
while read -r n f m <&3 || [ -n "${n:-}" ]; do
  case "$n" in ''|'#'*) continue;; esac
  [ -n "${f:-}" ] && [ -n "${m:-}" ] || { note "GATE flows: bad line in $FLOWS"; exit 1; }
  MT_LIMIT=460 mt "$n" "$f" || { if [ -n "$(find "$RAW/m-$n" "$RAW/m-$n-again" -name "05-no-record-7-months*.png" -print 2>/dev/null)" ]; then
      note "GATE data FAIL: $n no photo record in this month + 6 back on the home the app opened (premise: caregiver pair, 1 home, record in October)"; fi
    flow_fail "$m"; }
done 3< "$FLOWS"
say "flow passed"
exit 0
