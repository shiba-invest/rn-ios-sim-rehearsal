#!/bin/bash








set -u
U="$1"; F="$2"; P=22087
. "$(dirname "$0")/cm-lim.sh"
cls() { perl -ne 'print "$1\n" if /\b([A-Za-z]{2,40}(?:Exception|Error|Timeout|Failure|Unreachable))\b/' | awk '!s[$0]++ && ++n <= 3' | paste -sd, - || true; }
O=$(DF="$F" limf 10 perl -e '
  my ($n, %k, @l) = (0); my @order = qw(json at exc warn info blank other);
  open(my $h, "<", $ENV{DF}) or do { print "lines=0 kinds=none last3=-"; exit 0 };
  while (my $x = <$h>) { $x =~ s/\r//g; $x =~ s/\e\[[0-9;]*[A-Za-z]//g; $n++;
    my $t = $x =~ /^\s*$/ ? "blank" : $x =~ /^\s+at\s/ ? "at" : $x =~ /(Exception|Error|Failure)/ ? "exc" : $x =~ /\bWARN/i ? "warn"
      : $x =~ /\b(INFO|DEBUG)\b/ ? "info" : $x =~ /^\s*[\{\}\[\]"]/ ? "json" : "other";
    $k{$t}++; push @l, $t; shift @l if @l > 3; }
  print "lines=$n kinds=" . join(",", map { "$_:" . ($k{$_} || 0) } @order) . " last3=" . (join(",", @l) || "-");' 2>/dev/null) || O="lines=? kinds=cut last3=-"
C=$(limf 10 cat "$F" 2>/dev/null | cls) || C=""
echo "out ${O% last3=*} classes=${C:--} last3=${O##* last3=}"
pc() { { limf 10 pgrep -f "$1" 2>/dev/null || true; } | grep -c '[0-9]' || true; }
rn=$(pc "xcodebuild test-without-building.*$U"); dr=$(pc "maestro-driver-iosUITests")
pt=$({ limf 10 lsof -nP -iTCP:$P -sTCP:LISTEN -t 2>/dev/null || true; } | grep -c '[0-9]' || true); [ "${pt:-0}" = 0 ] && pt=closed || pt=open
lg() { local L; L=$(ls -t $1 2>/dev/null) || true; L="${L%%$'\n'*}"
  if [ -z "$L" ]; then echo none; else L=$(limf 10 tail -n 300 "$L" 2>/dev/null | cls) || L=""; echo "${L:--}"; fi; }
echo "sys runner=${rn:-0} driver=${dr:-0} port=$pt mlog=$(lg "$HOME/.maestro/tests/*/maestro.log") xlog=$(lg "$HOME/Library/Logs/maestro/xctest_runner_logs/*.log")"
exit 0
