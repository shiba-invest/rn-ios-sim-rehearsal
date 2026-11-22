


CM_ROOT="${CM_ROOT:-$PWD}"; HOME="${HOME:-$CM_ROOT}"; mkdir -p "$CM_ROOT/out/logs"
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






cm_say() { echo "$*"; echo "$*" >> "$CM_ROOT/out/logs/causes.txt" 2>/dev/null || true; }
case "${CM_STEP:-}" in ''|probe|status) ;; *) if [ "$(cm_left)" -le 0 ]; then cm_say "DEADLINE: step ${CM_STEP} not started (second $CM_DEADLINE_SEC passed)"; exit 1; fi;; esac


CM_GHT="${GH_STATUS_TOKEN:-}"
case "${CM_STEP:-}" in ''|probe|status) ;; *) export -n GH_STATUS_TOKEN 2>/dev/null || true;; esac

cm_need_values() { local i="${E2E_0003_LOGIN:-}" p="${E2E_0003_PASSWORD:-}"
  if [ "${#i}" -ge 1 ] && [ "${#p}" -ge 4 ] && [ -n "$CM_GHT" ]; then echo "values ok (lengths only)"; return 0; fi
  cm_say "GATE a FAIL: values missing or short (id=$([ "${#i}" -ge 1 ] && echo ok || echo empty) pw=$([ "${#p}" -ge 4 ] && echo ok || echo short) token=$([ -n "$CM_GHT" ] && echo set || echo empty))"; return 1; }

lim() { local s="$1"; shift; local left; left=$(cm_left)
  if [ "$left" -le 0 ]; then echo "DEADLINE: second $CM_DEADLINE_SEC passed, not starting $1" >&2; return 142; fi
  local cut=0; if [ "$left" -lt "$s" ]; then echo "lim: $1 limited to ${left}s by the deadline" >&2; s="$left"; cut=1; fi
  local r=0; limf "$s" "$@" || r=$?

  if [ "$cut" = 1 ] && [ "$r" = 142 ]; then echo "DEADLINE hit: $1 cut at ${s}s by the deadline (second $CM_DEADLINE_SEC) in step ${CM_STEP:-?}" >> "$CM_ROOT/out/logs/causes.txt" 2>/dev/null || true; fi
  return "$r"; }


expect() { if grep -q -F -- "$2" "$1"; then echo "PREDICT ok [$3] $2"; else echo "PREDICT FAIL [$3]: expected line not seen: $2"; exit 1; fi; }









cm_quiet() { local r=0
  if command -v pkill >/dev/null 2>&1; then
    pkill -INT -f 'simctl io .* recordVideo' 2>/dev/null || true; pkill -f '^log stream' 2>/dev/null || true; fi
  command -v xcrun >/dev/null 2>&1 || return 0
  limf 200 xcrun simctl list devices booted > "$HOME/cm-booted.txt" 2>/dev/null || true
  if grep -q '(Booted)' "$HOME/cm-booted.txt" 2>/dev/null; then
    limf 30 xcrun simctl shutdown all || r=$?; echo "publish: simulators shut down first (rc=$r)"; fi; return 0; }


cm_publish() { local rc0=$? r=0 t0 ctx
  case "${CM_STEP:-}" in ''|probe|status) ;; *) local lf; lf=$(cm_left); echo "step ${CM_STEP} rc=$rc0 left=$lf" >> "$CM_ROOT/out/logs/causes.txt" 2>/dev/null || true
     if [ "$rc0" -ne 0 ] && [ "$lf" -le 0 ]; then echo "DEADLINE hit in step ${CM_STEP} (rc=$rc0, second $CM_DEADLINE_SEC passed)" >> "$CM_ROOT/out/logs/causes.txt" 2>/dev/null || true; fi;; esac
  cm_quiet; t0=$(date +%s)
  LOGIN_ID="${LOGIN_ID:-${E2E_0003_LOGIN:-}}" LOGIN_PW="${LOGIN_PW:-${E2E_0003_PASSWORD:-}}" GH_STATUS_TOKEN="${CM_GHT:-}" \
    limf 160 node "$CM_ROOT/.maestro/cm-scrub.js" "$CM_ROOT/out" "$HOME/cm-withheld" "$HOME/cm-count.txt" > "$HOME/cm-publish.log" 2>&1 || r=$?
  if [ "$r" -ne 0 ]; then
    mkdir -p "$CM_ROOT/upload"; echo "publish-failed scrub rc=$r seconds=$(( $(date +%s) - t0 )) step=${CM_STEP:-?}" > "$CM_ROOT/upload/publish-failed.txt"
    echo "publish: scrub rc=$r after $(( $(date +%s) - t0 )) s, nothing of out/ copied to upload/ (summary below: keys and verdicts only)"
    grep -rh -E '^(PROBE summary|FACT |GATE |iphone rc=|flow [a-z-]+ rc=)' "$CM_ROOT/out" > "$HOME/cm-summary.txt" 2>/dev/null || true
    sed -E 's/^(FACT [a-z0-9.-]+) .* (verdict=[A-Z]+)$/\1 \2/; s/^(GATE [a-z]+ (ok|FAIL)).*/\1/' "$HOME/cm-summary.txt" | awk '!s[$0]++' || true
    case "${CM_STEP:-}" in probe) ctx=codemagic/stage1-probe;; *) ctx=codemagic/ios-sim-verify;; esac
    GH_STATUS_TOKEN="${CM_GHT:-}" limf 30 node "$CM_ROOT/.maestro/cm-ghstatus.js" "$ctx" failure "no records: scrub rc=$r" || true; return 0; fi
  mkdir -p "$CM_ROOT/upload" && cp -R "$CM_ROOT/out/." "$CM_ROOT/upload/" && echo "publish: $(grep '^secret-count total' "$HOME/cm-publish.log" || echo 'no total line')"; }
