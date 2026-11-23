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
if [ "${PWAF:-0}" = 1 ]; then i=0 # practice only (Maestro known-issues, E section 29): password AutoFill off in the two plists, no SpringBoard restart
  for p in "$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/UserConfigurationProfiles/EffectiveUserSettings.plist" "$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/UserSettings.plist"; do i=$((i + 1))
    if [ -f "$p" ]; then b=$(plutil -extract restrictedBool.allowPasswordAutoFill.value raw "$p" 2>/dev/null || echo none); r=0; plutil -replace restrictedBool.allowPasswordAutoFill.value -bool NO "$p" 2>/dev/null || r=$?
      note "pwaf plist$i present=1 before=$b rc=$r after=$(plutil -extract restrictedBool.allowPasswordAutoFill.value raw "$p" 2>/dev/null || echo none)"
    else note "pwaf plist$i present=0 (left as is, run goes on)"; fi; done; fi
lim 300 xcrun simctl install "$UDID" "$APP" || { r=$?; note "GATE install: failed (rc $r; 142 = over the limit)"; exit 1; }

start_rec() { [ -z "$REC" ] || return 0
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/raw.mp4" >/dev/null 2>&1 &
  REC=$!; sleep 2; }

memlog() { # practice only: free memory (free+inactive+speculative pages) to out/logs/mem.txt, numbers only
  local p; p=$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)
  echo "$(date -u +%H:%M:%S) $1 free_mb=$(( $(vm_stat | awk '/Pages free|Pages inactive|Pages speculative/ {gsub(/[.]/,"",$NF); s+=$NF} END {print s+0}') * p / 1048576 ))" >> "$CM_ROOT/out/logs/mem.txt" 2>/dev/null || true; }
portlog() { # practice only: driver port 22087 LISTEN count, runner and xcodebuild-twb process counts (numbers only)
  local l rn xb; l=$(lsof -nP -iTCP:22087 -sTCP:LISTEN 2>/dev/null | grep -c LISTEN); rn=$(pgrep -f "maestro-driver-iosUITests" 2>/dev/null | grep -c .)
  xb=$(pgrep -f "xcodebuild test-without-building" 2>/dev/null | grep -c .)
  echo "$(date -u +%H:%M:%S) $(date +%s) $1 port22087-listen=$l runner-pid=$rn xcodebuild-twb=$xb" >> "$CM_ROOT/out/logs/port.txt" 2>/dev/null || true; }
zero_step() { # <name>: 0 when the console of that maestro run has no step line at all; notes class names + exit numbers only
  local n="$1" c="$RAW/m-$1.console" k cc rl rc ex
  k=$(node rehearsal/steps.js "$c" 0 2>/dev/null | awk '$2 != "other" && $2 != "device" && $2 != "flow-start"' | grep -c .)
  [ "$k" -eq 0 ] || return 1
  cc=$(node rehearsal/steps.js "$c" 0 2>/dev/null | grep -o 'class=[A-Za-z]*' | cut -d= -f2 | awk '!s[$0]++' | head -3 | tr '\n' ',')
  rl=$(find "$RAW/m-$n" "$HOME/.maestro/tests" -name 'xctest_runner*.log' -newer "$CM_ROOT/out/t0" 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
  if [ -n "$rl" ]; then
    rc=$(tail -200 "$rl" | grep -o -E '\b[A-Z][A-Za-z]*(Exception|Error|Timeout|Failure|Unreachable)\b' | awk '!s[$0]++' | head -3 | tr '\n' ',')
    ex=$(tail -200 "$rl" | grep -o -i -E '(exit(ed)?( with)? (code|status)|exit code)[ :=]*[0-9]+' | grep -o -E '[0-9]+$' | tail -1)
    note "zero-step $n console-classes=${cc:-none} runner-log=found runner-classes=${rc:-none} exit=${ex:-none}"
  else note "zero-step $n console-classes=${cc:-none} runner-log=none"; fi
  return 0; }
zs_clean() { # E section 27: runner only, this UDID's xcodebuild only, wait for the port to close (max 10 s)
  local i=0; limf 30 xcrun simctl terminate "$UDID" dev.mobile.maestro-driver-iosUITests.xctrunner >/dev/null 2>&1 || true
  limf 15 pkill -f "xcodebuild test-without-building.*$UDID" >/dev/null 2>&1 || true
  while [ $i -lt 10 ] && lsof -nP -iTCP:22087 -sTCP:LISTEN >/dev/null 2>&1; do sleep 1; i=$((i + 1)); done
  note "zero-step clean done waited=${i}s port22087-listen=$(lsof -nP -iTCP:22087 -sTCP:LISTEN 2>/dev/null | grep -c LISTEN)"; }
evid() { # <name>: after a failed maestro run: hierarchy line count and fixed alert words (counts only, the text stays outside out/), runner log tail class names
  local n="$1" h="$RAW/ev-$1.txt" r=0 w o="" rl rc
  lim 200 maestro --device "$UDID" hierarchy --compact > "$h" 2>&1 < /dev/null || r=$?
  for w in SpringBoard Alert Password "Not Now" "Save Password" Compromised "Security Recommendations" パスワード 今はしない 保存 漏えい ホーム ログイン; do o="$o $(echo "$w" | tr -d ' ')=$(grep -c -F "$w" "$h")"; done
  rl=$(find "$RAW/m-$n" "$HOME/.maestro/tests" -name 'xctest_runner*.log' -newer "$CM_ROOT/out/t0" 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
  [ -n "$rl" ] && rc=$(tail -200 "$rl" | grep -o -E '\b[A-Z][A-Za-z]*(Exception|Error|Timeout|Failure|Unreachable)\b' | awk '!s[$0]++' | head -3 | tr '
' ',')
  note "evidence $n hierarchy-rc=$r lines=$(grep -c . "$h")$o springboard-lines=$(grep -c -i springboard "$h") springboard-alert-lines=$(grep -i springboard "$h" | grep -c -i alert) runner-log=$([ -n "$rl" ] && echo found || echo none) runner-classes=${rc:-none}"; }
mt() { # <name> <flow> [-e ...]: one maestro test, debug output outside out/; returns its rc
  local n="$1" f="$2"; shift 2; local r=0
  memlog "before $n"; portlog "before $n"
  lim "${MT_LIMIT:-300}" maestro --device "$UDID" test --test-output-dir "$RAW/m-$n" -e ORIENT="$O" "$@" ".maestro/$f" > "$RAW/m-$n.console" 2>&1 < /dev/null || r=$?
  memlog "after $n rc=$r"; portlog "after $n rc=$r"
  note "flow $n rc=$r (142 = over the limit) at $(date -u +%H:%M:%S)"
  if [ "$r" -ne 0 ] || grep -q -E '\b[A-Z][A-Za-z]*(Exception|Failure)\b' "$RAW/m-$n.console" 2>/dev/null; then evid "$n"; fi
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
  MT_LIMIT="${MT_HOME:-610}" mt "home-$1" trial-home.yaml || r=$?
  if [ "$r" -ne 0 ] && zero_step "home-$1"; then # one retry of the same flow after a zero-step run (ZS_CLEAN=0 = no clean, control)
    ZS=$((ZS + 1)); if [ "${ZS_CLEAN:-1}" = 1 ]; then zs_clean; else note "zero-step clean skipped (control)"; fi
    r=0; MT_LIMIT="${MT_HOME:-610}" mt "home-$1-zs" trial-home.yaml || r=$?; note "zero-step retry home-$1 rc=$r"; fi
  kill "$sp" 2>/dev/null || true; wait "$sp" 2>/dev/null || true
  note "login $1 enter-to-result-s(with the Maestro CLI start)=$(( $(date +%s) - ENTER_AT )) home=$([ "$r" -eq 0 ] && echo yes || echo no)"
  return "$r"
}
login_net_msg() { # 0 when a non-credential login failure is on screen (a1a.tsx:83 network, :84 general). The tree is searched, never saved.
  memlog "before hierarchy"
  local h; h=$(lim 200 maestro --device "$UDID" hierarchy 2>/dev/null) || return 1
  case "$h" in *"ログインできませんでした。通信環境をご確認ください"*|*"ログインできませんでした。もう一度お試しください"*) return 0;; *) return 1;; esac
}
flow_fail() { note "flow failed ($1)"; lim 115 bash .maestro/netcheck.sh "$NET" "after-fail" >/dev/null 2>&1 || true; exit 1; }
fault_hook() { local fh="${FAULT_HOOK:-}"; [ -n "$fh" ] || return 0; bash "$fh" "$1" "$UDID" || true; }
FLOWS=.maestro/cm-flows.txt
[ -f "$FLOWS" ] || { note "GATE flows: $FLOWS missing"; exit 1; }

if [ "${DRV_ONLY:-0}" = 1 ]; then # practice only: the driver piece alone (boot above -> hierarchy --compact x2 -> shutdown)
  for i in 1 2; do [ "$i" = 1 ] && DT="${DRV_T1:-993000}" || DT="${DRV_T2:-540000}"; s=$(date +%s); r=0; portlog "before drv $i"
    MAESTRO_DRIVER_STARTUP_TIMEOUT="$DT" lim 1300 maestro --device "$UDID" hierarchy --compact > "$RAW/drv-$i.txt" 2>&1 < /dev/null || r=$?
    k=$(grep -o -E '\b[A-Z][A-Za-z]*(Exception|Error|Timeout|Failure|Unreachable)\b' "$RAW/drv-$i.txt" | awk '!s[$0]++' | head -3 | tr '
' ',')
    note "drv $i startup-timeout-ms=$DT s=$(( $(date +%s) - s )) rc=$r class=${k:-none} lines=$(grep -c . "$RAW/drv-$i.txt")"; portlog "after drv $i rc=$r"; done
  r=0; limf 60 xcrun simctl shutdown "$UDID" || r=$?; note "drv shutdown rc=$r"; say "drv done"; exit 0; fi
ZS=0
fault_hook pre-login
lim 115 bash .maestro/netcheck.sh "$NET" "pre-login" >/dev/null 2>&1 || true
MT_LIMIT="${MT_LOGIN:-1180}" mt login trial-login.yaml -e LOGIN_ID="$LID" -e LOGIN_PW="$LPW" || { zero_step login || true; flow_fail "login form, before the Enter key"; }
fault_hook post-enter
fault_hook pre-home
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
  MT_LIMIT="${MT_LIST:-460}" mt "$n" "$f" || { if [ -n "$(find "$RAW/m-$n" -name "05-no-record-7-months*.png" -print 2>/dev/null)" ]; then
      note "GATE data FAIL: $n no photo record in 7 months on the home the app opened (fresh simulator = first assigned home)"; fi
    flow_fail "$m"; }
done 3< "$FLOWS"
note "zero-step-retries=$ZS"; say "flow passed"
exit 0
