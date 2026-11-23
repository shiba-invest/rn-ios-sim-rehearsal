#!/bin/bash









set -u
U="$1"
. "$(dirname "$0")/cm-lim.sh"
r=0; T=$(MAESTRO_DRIVER_STARTUP_TIMEOUT=60000 limf 85 maestro --device "$U" hierarchy 2>/dev/null < /dev/null) || r=$?
n=0; [ -z "$T" ] || n=$(printf '%s\n' "$T" | wc -l | tr -d ' ')
o=$(printf '%s\n' "$T" | perl -e 'local $/; my $t = <STDIN>; my @w = ("Save Password", "Use Strong Password", "Update Password",
  "パスワードを保存", "強力なパスワード", "パスワードを更新", "Allow Paste", "ペーストを許可", "Would Like to Send You Notifications",
  "通知を送信", "Not Now", "今はしない"); my $h = "-"; for my $x (@w) { if (index($t, $x) >= 0) { $h = $x; last } }
  my $a = ($h ne "-" || $t =~ /SpringBoard|com\.apple\.springboard|SBUserNotification|XCUIElementTypeAlert/) ? "yes" : "no";
  $h = "other" if $a eq "yes" && $h eq "-"; print "springboard-alert=$a heading=$h";' 2>/dev/null) || o=""
case "$o" in "springboard-alert="*) ;; *) o="springboard-alert=no heading=-";; esac
echo "screen: hierarchy rc=$r lines=$n $o"
exit 0
