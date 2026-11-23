#!/bin/bash















set -u
P=22087
. "$(dirname "$0")/cm-lim.sh"
sysc() { local rp dp pp L=- Q=-
  rp=$({ limf 10 pgrep -f "[x]codebuild test-without-building.*$U" 2>/dev/null || true; } | grep '^[0-9][0-9]*$' || true)
  dp=$({ limf 10 pgrep -f "[m]aestro-driver-iosUITests" 2>/dev/null || true; } | grep '^[0-9][0-9]*$' || true)
  pp=$(printf '%s\n%s\n' "$rp" "$dp" | grep . | paste -sd, - || true)
  if [ -n "$pp" ]; then L=$({ limf 10 lsof -nP -a -p "$pp" -iTCP -sTCP:LISTEN -Fn 2>/dev/null || true; } | grep '^n' || true)
    Q=$(printf '%s\n' "$L" | grep -c ":$P\$" || true); L=$(printf '%s\n' "$L" | grep -c '^n' || true); fi
  echo "runner=$(printf '%s\n' "$rp" | grep -c . || true) driver=$(printf '%s\n' "$dp" | grep -c . || true) listen=$L p$P=$Q"; }
if [ "${1:-}" = --sample ]; then U="$2"; S="$3"; t0=$(date +%s); n=0; mr=0; md=0; ml=0
  while [ ! -f "$S.stop" ] && [ $(( $(date +%s) - t0 )) -lt 1300 ]; do sleep 5; n=$((n + 5)); [ $((n % 30)) = 0 ] || continue
    x=$(sysc); [ -f "$S.stop" ] && break; set -- $x; r=${1#*=}; d=${2#*=}; l=${3#*=}; [ "$r" -gt $mr ] && mr=$r; [ "$d" -gt $md ] && md=$d
    case "$l" in [0-9]*) [ "$l" -gt $ml ] && ml=$l;; esac; echo "$x t=$(( $(date +%s) - t0 )) peak=$mr:$md:$ml" > "$S.new" && mv -f "$S.new" "$S"; done; exit 0; fi
U="$1"; F="$2"; FE="${3:-}"; SM="${4:-}"
cls() { perl -ne 'print "$1\n" if /\b([A-Za-z]{2,40}(?:Exception|Error|Timeout|Failure|Unreachable))\b/' | awk '!s[$0]++ && ++n <= 3' | paste -sd, - || true; }
O=$(DF="$F" DE="$FE" limf 10 perl -e '
  my ($n, $e, %k, @l) = (0, 0); my @order = qw(tree at exc warn info blank other); my @x;
  for my $p ($ENV{DF}, $ENV{DE}) { my $h; next unless length $p && open($h, "<", $p); my @y = <$h>; $e = @y if $p eq $ENV{DE}; push @x, @y; }
  unless (@x) { print "lines=0 err=0 kinds=none last3=-"; exit 0 }
  for my $x (@x) { $x =~ s/\r//g; $x =~ s/\e\[[0-9;]*[A-Za-z]//g; $n++;
    my $t = $x =~ /^\s*$/ ? "blank" : $x =~ /^[0-9]/ ? "tree" : $x =~ /^\s+at\s/ ? "at" : $x =~ /(Exception|Error|Failure)/ ? "exc"
      : $x =~ /\bWARN/i ? "warn" : $x =~ /\b(INFO|DEBUG)\b/ ? "info" : "other";
    $k{$t}++; push @l, $t; shift @l if @l > 3; }
  print "lines=$n err=$e kinds=" . join(",", map { "$_:" . ($k{$_} || 0) } @order) . " last3=" . (join(",", @l) || "-");' 2>/dev/null) || O="lines=? err=? kinds=cut last3=-"
C=""; [ -z "$FE" ] || C=$(limf 10 cat "$FE" 2>/dev/null | cls) || C=""
echo "out ${O% last3=*} classes=${C:--} last3=${O##* last3=}"
lg() { local L; L=$(ls -t $1 2>/dev/null) || true; L="${L%%$'\n'*}"
  if [ -z "$L" ]; then echo none; else L=$(limf 10 tail -n 300 "$L" 2>/dev/null | cls) || L=""; echo "${L:--}"; fi; }
echo "sys $(sysc) mlog=$(lg "$HOME/.maestro/tests/*/maestro.log") xlog=$(lg "$HOME/Library/Logs/maestro/xctest_runner_logs/*.log")"
x=""; [ -n "$SM" ] && [ -f "$SM" ] && x=$(head -1 "$SM" 2>/dev/null); echo "smp ${x:-none}"
exit 0
