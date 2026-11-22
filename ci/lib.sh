# Shared helpers for the rehearsal scripts. Source it: . ci/lib.sh
# OUT holds everything that is uploaded; WITHHELD holds files the sweep keeps back (never uploaded).
OUT="${OUT:-$PWD/out}"
WITHHELD="${WITHHELD:-$PWD/withheld}"
mkdir -p "$OUT" "$WITHHELD"

now() { date +%s; }
stamp() { date -u +%H:%M:%S; }
note() { echo "[$(stamp)] $*" | tee -a "$OUT/notes.txt" >&2; }

# lim SECONDS cmd args...  Runs cmd in its own process group; on time-out kills the whole group, returns 142.
lim() {
  local secs="$1"; shift
  perl -e '
    my $secs = shift @ARGV;
    my $pid = fork();
    die "fork failed" unless defined $pid;
    if ($pid == 0) { setpgrp(0, 0); exec { $ARGV[0] } @ARGV; exit 127; }
    $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 3; kill "KILL", -$pid; waitpid($pid, 0); exit 142; };
    alarm $secs;
    waitpid($pid, 0);
    my $st = $?;
    exit(($st & 127) ? 128 + ($st & 127) : $st >> 8);
  ' "$secs" "$@"
}

# timed NAME CAP cmd args...  Runs cmd under lim, writes "name seconds rc cap" to steps.tsv.
# A non-zero rc also writes stopped-at.txt (first stop wins) and is returned.
timed() {
  local name="$1" cap="$2"; shift 2
  local t0 t1 rc was=$-
  t0=$(now)
  set +e
  lim "$cap" "$@"
  rc=$?
  case "$was" in *e*) set -e ;; esac
  t1=$(now)
  printf '%s\t%s\t%s\t%s\n' "$name" "$((t1 - t0))" "$rc" "$cap" >> "$OUT/steps.tsv"
  note "step $name seconds=$((t1 - t0)) rc=$rc cap=$cap"
  if [ "$rc" -ne 0 ] && [ ! -f "$OUT/stopped-at.txt" ]; then
    echo "$name rc=$rc" > "$OUT/stopped-at.txt"
  fi
  return "$rc"
}
