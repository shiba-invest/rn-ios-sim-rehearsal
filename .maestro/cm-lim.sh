


CM_ROOT="${CM_ROOT:-$PWD}"; mkdir -p "$CM_ROOT/out/logs"
[ -f "$CM_ROOT/out/t0" ] || date +%s > "$CM_ROOT/out/t0"
CM_DEADLINE_SEC="${CM_DEADLINE_SEC:-1866}"


limf() { local s="$1"; shift; local t0 r=0; t0=$(date +%s); perl -e 'my $s = shift @ARGV; my $pid = fork; defined $pid or exit 127;
  if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127; }
  $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 5; kill "KILL", -$pid; waitpid($pid, 0); exit 142; };
  alarm $s; waitpid($pid, 0); my $st = $?; alarm 0;
  exit(($st & 127) ? 128 + ($st & 127) : ($st >> 8));' "$s" "$@" || r=$?
  cm_time "$s" "$(( $(date +%s) - t0 ))" "$r" "$1"; return $r; }




case "${1:-}" in step=*) CM_STEP="${1#step=}";; esac
cm_time() { local j=1 at f
  case " ${FUNCNAME[*]} " in *" cm_publish "*) at=publish;; *)
    while [ "$j" -lt "${#FUNCNAME[@]}" ]; do case "${FUNCNAME[$j]}" in lim|limf|rd|mt) j=$((j + 1));; *) break;; esac; done
    f=$(basename "${BASH_SOURCE[$j]:-x}")
    case "$f" in cm-*.sh|netcheck.sh) at="$f:${BASH_LINENO[$((j - 1))]}";; *) at="yaml-${CM_STEP:-?}:${BASH_LINENO[$((j - 1))]}";; esac;; esac
  echo "$at limit=$1 took=$2 rc=$3 cmd=$(basename "$4")" >> "$CM_ROOT/out/logs/lim-times.txt" 2>/dev/null || true; }
cm_left() { echo $(( $(cat "$CM_ROOT/out/t0") + CM_DEADLINE_SEC - $(date +%s) )); }

lim() { local s="$1"; shift; local left; left=$(cm_left)
  if [ "$left" -le 0 ]; then echo "DEADLINE: second $CM_DEADLINE_SEC passed, not starting $1" >&2; return 142; fi
  if [ "$left" -lt "$s" ]; then echo "lim: $1 limited to ${left}s by the deadline" >&2; s="$left"; fi
  limf "$s" "$@"; }


expect() { if grep -q -F -- "$2" "$1"; then echo "PREDICT ok [$3] $2"; else echo "PREDICT FAIL [$3]: expected line not seen: $2"; exit 1; fi; }









cm_quiet() { local r=0
  if command -v pkill >/dev/null 2>&1; then
    pkill -INT -f 'simctl io .* recordVideo' 2>/dev/null || true; pkill -f '^log stream' 2>/dev/null || true; fi
  command -v xcrun >/dev/null 2>&1 || return 0
  limf 20 xcrun simctl list devices booted > "$HOME/cm-booted.txt" 2>/dev/null || true
  if grep -q '(Booted)' "$HOME/cm-booted.txt" 2>/dev/null; then
    limf 30 xcrun simctl shutdown all || r=$?; echo "publish: simulators shut down first (rc=$r)"; fi; return 0; }
cm_publish() { local r=0 t0 ctx; cm_quiet; t0=$(date +%s)
  LOGIN_ID="${LOGIN_ID:-${E2E_0003_LOGIN:-}}" LOGIN_PW="${LOGIN_PW:-${E2E_0003_PASSWORD:-}}" \
    limf 120 node "$CM_ROOT/.maestro/cm-scrub.js" "$CM_ROOT/out" "$HOME/cm-withheld" "$HOME/cm-count.txt" > "$HOME/cm-publish.log" 2>&1 || r=$?
  if [ "$r" -ne 0 ]; then
    mkdir -p "$CM_ROOT/upload"; echo "publish-failed scrub rc=$r seconds=$(( $(date +%s) - t0 )) step=${CM_STEP:-?}" > "$CM_ROOT/upload/publish-failed.txt"
    echo "publish: scrub rc=$r after $(( $(date +%s) - t0 )) s, nothing of out/ copied to upload/ (summary below: keys and verdicts only)"
    grep -rh -E '^(PROBE summary|FACT |GATE |iphone rc=|flow [a-z-]+ rc=)' "$CM_ROOT/out" > "$HOME/cm-summary.txt" 2>/dev/null || true
    sed -E 's/^(FACT [a-z0-9.-]+) .* (verdict=[A-Z]+)$/\1 \2/; s/^(GATE [a-z]+ (ok|FAIL)).*/\1/' "$HOME/cm-summary.txt" | awk '!s[$0]++' || true
    case "${CM_STEP:-}" in probe) ctx=codemagic/stage1-probe;; *) ctx=codemagic/ios-sim-verify;; esac
    limf 30 node "$CM_ROOT/.maestro/cm-ghstatus.js" "$ctx" failure "no records: scrub rc=$r" || true; return 0; fi
  mkdir -p "$CM_ROOT/upload" && cp -R "$CM_ROOT/out/." "$CM_ROOT/upload/" && echo "publish: $(grep '^secret-count total' "$HOME/cm-publish.log" || echo 'no total line')"; }
