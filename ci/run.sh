#!/bin/bash
# iPhone run: install, launch, driver start (gate c), log stream with a size cap, video, timed shots,
# login -> wait -> (only after the network message) one resubmit -> wait. Never a third try.
# FAULT: none | a (block auth host, restore during the wait) | b (keep blocked) | c-up (as a, keyboard up
# before the resubmit) | d-cold / d-cap (boot, handled in gate a) | e (unfiltered log to hit the cap, planted secret).
# Exit codes: 0 pass, 14 gate c, 21 login flow, 22 stopped after one resubmit, 23 no home and no network message,
# 24 resubmit flow failed, 15 install/launch.
set -o pipefail
. ci/lib.sh
FAULT="${FAULT:-none}"
UDID=$(cat "$OUT/udid.txt")
APP=$(cat "$OUT/app-path.txt")
BID=dev.rehearsal.sim
HOST="cognito-idp.${AUTH_REGION}.amazonaws.com"
BLACKHOLE=192.0.2.1
LOG_CAP="${LOG_CAP_BYTES:-52428800}"
export MAESTRO_CLI_NO_ANALYTICS=1 MAESTRO_DRIVER_STARTUP_TIMEOUT=300000
M=(maestro --device "$UDID")
ENVS=(-e "LOGIN_ID=${LOGIN_ID}" -e "LOGIN_PW=${LOGIN_PW}" -e "ORIENT=PORTRAIT")
RC=0

finish() {
  RC="$1"; shift
  note "finish rc=$RC $*"
  [ -n "${VIDPID:-}" ] && kill -INT "$VIDPID" 2>/dev/null && sleep 3
  [ -n "${SHOTPID:-}" ] && kill "$SHOTPID" 2>/dev/null
  pkill -f "simctl spawn $UDID log stream" 2>/dev/null || true
  sleep 1
  bytes=$(wc -c < "$OUT/sim.log" | tr -d ' ')
  capped=no; [ "$bytes" -ge "$LOG_CAP" ] && capped=yes
  note "sim.log bytes=$bytes cap=$LOG_CAP capped=$capped"
  grep -a '\[REHEARSAL\]' "$OUT/sim.log" > "$OUT/app-lines.txt" 2>/dev/null || true
  [ "$FAULT" = a ] || [ "$FAULT" = b ] || [ "$FAULT" = c-up ] && unblock || true
  printf 'fault=%s rc=%s stopped=%s %s\n' "$FAULT" "$RC" "$(cat "$OUT/stopped-at.txt" 2>/dev/null || echo none)" "$*" > "$OUT/result.txt"
  exit "$RC"
}

flushdns() { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder 2>/dev/null || true; }
hostcheck() {
  curl -s -o /dev/null -w '%{http_code}' --max-time "$1" -X POST -H 'Content-Type: application/x-amz-json-1.1' \
    -H 'X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth' --data '{}' "https://$HOST/" || true
}
block() {
  sudo sh -c "echo '$BLACKHOLE $HOST' >> /etc/hosts"
  echo "block drop out quick inet from any to $BLACKHOLE" | sudo pfctl -a com.apple/rehearsal -f - 2>>"$OUT/pf.txt"
  sudo pfctl -E >>"$OUT/pf.txt" 2>&1 || true
  flushdns
  note "blocked $HOST -> $BLACKHOLE host-check http=$(hostcheck 8)"
}
unblock() {
  grep -q "$BLACKHOLE $HOST" /etc/hosts || return 0
  sudo sed -i '' "/$BLACKHOLE $HOST/d" /etc/hosts
  sudo pfctl -a com.apple/rehearsal -F rules >>"$OUT/pf.txt" 2>&1 || true
  flushdns
  note "restored $HOST host-check http=$(hostcheck 15)"
}
netmsg() { grep -q '通信環境をご確認ください' "$1"; }

timed install 180 xcrun simctl install "$UDID" "$APP" || finish 15 install
timed launch 60 xcrun simctl launch "$UDID" "$BID" || finish 15 launch

# Device log with a byte cap (the stream ends when head stops reading).
if [ "$FAULT" = e ]; then LVL=debug; PRED=(); else
  LVL=info
  PRED=(--predicate 'process == "Rehearsal" OR subsystem BEGINSWITH "com.apple.network" OR subsystem == "com.apple.CFNetwork"')
fi
( xcrun simctl spawn "$UDID" log stream --style compact --level "$LVL" "${PRED[@]}" 2>/dev/null | head -c "$LOG_CAP" > "$OUT/sim.log" ) &
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/screen.mp4" >/dev/null 2>&1 &
VIDPID=$!
( t=0; for s in 3 15 40 70; do sleep $((s - t)); t=$s; xcrun simctl io "$UDID" screenshot "$OUT/shot-${s}s.png" >/dev/null 2>&1; done ) &
SHOTPID=$!

# Gate c: the first Maestro call starts the driver; its seconds are the driver start time.
timed driver-start 360 "${M[@]}" hierarchy > "$OUT/hierarchy-start.json" || finish 14 gate-c
grep -q 'れんしゅう' "$OUT/hierarchy-start.json" || { echo "gate-c rc=14" > "$OUT/stopped-at.txt"; finish 14 gate-c-text; }

case "$FAULT" in a|b|c-up) block ;; esac

timed login 240 "${M[@]}" test "${ENVS[@]}" --test-output-dir "$OUT/m-login" flows/login.yaml || finish 21 login
note "enter pressed"
if [ "$FAULT" = a ] || [ "$FAULT" = c-up ]; then
  ( sleep "${RESTORE_AFTER:-40}"; unblock ) &
fi

if timed wait-1 200 "${M[@]}" test --test-output-dir "$OUT/m-wait1" flows/login-wait.yaml; then
  rm -f "$OUT/stopped-at.txt"
  [ "$FAULT" = e ] && {
    echo "planted ${LOGIN_PW} ${PLANT_MARKER}" > "$OUT/planted-note.txt"
    for i in $(seq 1 48); do [ "$(wc -c < "$OUT/sim.log")" -ge "$LOG_CAP" ] && break; sleep 5; done
  }
  finish 0 "home after first try"
fi

"${M[@]}" hierarchy > "$OUT/hierarchy-after-try1.json" 2>/dev/null || true
netmsg "$OUT/hierarchy-after-try1.json" || finish 23 "no home and no network message"
rm -f "$OUT/stopped-at.txt"
note "network message seen after try 1"
xcrun simctl io "$UDID" screenshot "$OUT/try1-message.png" >/dev/null 2>&1 || true
sleep 30
if [ "$FAULT" = c-up ]; then
  "${M[@]}" test --test-output-dir "$OUT/m-kbup" flows-extra/keyboard-up.yaml || note "keyboard-up flow rc=$?"
  xcrun simctl io "$UDID" screenshot "$OUT/before-resubmit-keyboard.png" >/dev/null 2>&1 || true
fi
timed retry 120 "${M[@]}" test --test-output-dir "$OUT/m-retry" flows/login-retry.yaml || finish 24 retry
if timed wait-2 200 "${M[@]}" test --test-output-dir "$OUT/m-wait2" flows/login-wait.yaml; then
  rm -f "$OUT/stopped-at.txt"
  finish 0 "home after one resubmit"
fi
"${M[@]}" hierarchy > "$OUT/hierarchy-after-try2.json" 2>/dev/null || true
xcrun simctl io "$UDID" screenshot "$OUT/try2-stop.png" >/dev/null 2>&1 || true
finish 22 "stopped after one resubmit (message after try 2: $(netmsg "$OUT/hierarchy-after-try2.json" && echo yes || echo no))"
