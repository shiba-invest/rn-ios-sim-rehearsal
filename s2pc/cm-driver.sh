#!/bin/bash













set -u
U="$1"; P=22087; BID=dev.mobile.maestro-driver-iosUITests.xctrunner
. "$(dirname "$0")/cm-lim.sh"
r=0; limf 30 xcrun simctl terminate "$U" "$BID" >/dev/null 2>&1 || r=$?
case "$r" in 0) a="stopped";; 142) a="cut at 30 s";; *) a="was not running";; esac; echo "driver clean-up 1/3 driver app: $a"
r=0; limf 10 pkill -f "xcodebuild test-without-building.*$U" >/dev/null 2>&1 || r=$?
case "$r" in 0) a="stopped";; 142) a="cut at 10 s";; *) a="none";; esac; echo "driver clean-up 2/3 runner of this simulator: $a"
lsn() { { limf 10 lsof -nP -iTCP:$P -sTCP:LISTEN -t 2>/dev/null || true; } | grep -c '[0-9]' || true; }
S=$(date +%s); k=0; c=$(lsn)
if [ "${c:-0}" = 0 ]; then a="no listener"; else
  while [ "$k" -lt 10 ]; do limf 10 sleep 1 || true; k=$((k + 1)); c=$(lsn); [ "${c:-0}" != 0 ] || break; done
  if [ "${c:-0}" = 0 ]; then a="listener gone after $(( $(date +%s) - S )) s"; else a="listener left after 10 s"; fi; fi
echo "driver clean-up 3/3 port $P: $a"
L=$(ls -t "$HOME"/Library/Logs/maestro/xctest_runner_logs/*.log 2>/dev/null) || true; L="${L%%$'\n'*}"
if [ -z "$L" ]; then echo "driver log: no log"; else
  T=$(limf 10 tail -n 200 "$L" 2>/dev/null) || true
  C=$(printf '%s\n' "$T" | perl -ne 'print "$1\n" if /\b([A-Za-z]{2,40}(?:Exception|Error|Timeout|Failure|Unreachable))\b/' | awk '!s[$0]++ && ++n <= 3' | paste -sd, - || true)
  X=$(printf '%s\n' "$T" | perl -ne 'print "$1\n" if /\bexit(?:ed)?(?: with)?(?: code| status)[ :=]*(-?[0-9]{1,3})\b/i' | tail -n 1 || true)
  if [ -n "$C" ]; then o="classes $C"; else o="no class name"; fi; echo "driver log: $o${X:+ exit $X}"; fi
[ "$a" != "listener left after 10 s" ] || exit 3
exit 0
