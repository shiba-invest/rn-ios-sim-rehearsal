CM_ROOT="${CM_ROOT:-$PWD}"; mkdir -p "$CM_ROOT/out/logs"
[ -f "$CM_ROOT/out/t0" ] || date +%s > "$CM_ROOT/out/t0"
CM_DEADLINE_SEC="${CM_DEADLINE_SEC:-1866}"
limf() { local s="$1"; shift; perl -e 'my $s = shift @ARGV; my $pid = fork; defined $pid or exit 127;
  if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127; }
  $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 5; kill "KILL", -$pid; waitpid($pid, 0); exit 142; };
  alarm $s; waitpid($pid, 0); my $st = $?; alarm 0;
  exit(($st & 127) ? 128 + ($st & 127) : ($st >> 8));' "$s" "$@"; }
cm_left() { echo $(( $(cat "$CM_ROOT/out/t0") + CM_DEADLINE_SEC - $(date +%s) )); }
lim() { local s="$1"; shift; local left; left=$(cm_left)
  if [ "$left" -le 0 ]; then echo "DEADLINE: second $CM_DEADLINE_SEC passed, not starting $1" >&2; return 142; fi
  if [ "$left" -lt "$s" ]; then echo "lim: $1 limited to ${left}s by the deadline" >&2; s="$left"; fi
  limf "$s" "$@"; }
expect() { if grep -q -F -- "$2" "$1"; then echo "PREDICT ok [$3] $2"; else echo "PREDICT FAIL [$3]: expected line not seen: $2"; exit 1; fi; }
cm_publish() { local r=0
  LOGIN_ID="${LOGIN_ID:-${E2E_0003_LOGIN:-}}" LOGIN_PW="${LOGIN_PW:-${E2E_0003_PASSWORD:-}}" \
    limf 30 node "$CM_ROOT/.maestro/cm-scrub.js" "$CM_ROOT/out" "$HOME/cm-withheld" "$HOME/cm-count.txt" > "$HOME/cm-publish.log" 2>&1 || r=$?
  if [ "$r" -ne 0 ]; then echo "publish: scrub rc=$r, nothing copied to upload/"; return 0; fi
  mkdir -p "$CM_ROOT/upload" && cp -R "$CM_ROOT/out/." "$CM_ROOT/upload/" && echo "publish: $(grep '^secret-count total' "$HOME/cm-publish.log" || echo 'no total line')"; }
