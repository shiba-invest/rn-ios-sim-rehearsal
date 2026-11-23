#!/bin/bash














set -u
P="$1"; R="$HOME/cm-probe-raw"; mkdir -p "$R"
. "$(dirname "$0")/cm-lim.sh"
E=$(( $(date +%s) + 1915 ))
fact() { local v="${2:-}"; local e="$3"; local r
  if [ -z "$v" ]; then r=MISSING; elif [ "$e" = "-" ]; then r=RECORD; else case "$v" in *"$e"*) r=MATCH;; *) r=DIFF;; esac; fi
  echo "FACT $1 value=$v expect=$e verdict=$r"; }
fact arch "$(limf 10 uname -m 2>&1 | tr '\n' ' ' | sed 's/ *$//')" "arm64"
U=$(sed -n 's/^IPHONE_UDID=//p' "$P/sims.env" 2>/dev/null) || U=""; case "$U" in *$'\n'*) U="";; esac
if [ -z "$U" ]; then fact driver "skipped=no picked simulator (sim-pick failed)" "cold=ok warm=ok"; exit 0; fi

MV="${MAESTRO_VERSION:-}"; MS="${MAESTRO_ZIP_SHA256:-}"; MZ="$HOME/maestro-$MV.zip"; M="$HOME/.maestro/bin/maestro"; t=$(date +%s); mi=""
if [ -z "$MV" ] || [ -z "$MS" ]; then mi="failed: MAESTRO_VERSION or MAESTRO_ZIP_SHA256 not set"
elif ! limf 300 curl -fsSL -o "$MZ" "https://github.com/mobile-dev-inc/maestro/releases/download/cli-$MV/maestro.zip" 2>/dev/null; then mi="failed: download (rc 142 = over the limit)"
elif [ "$(shasum -a 256 "$MZ" | cut -c1-64)" != "$MS" ]; then mi="failed: sha256 differs"
elif ! limf 120 unzip -qo "$MZ" -d "$HOME/mz" >/dev/null 2>&1; then mi="failed: unzip"
else mkdir -p "$HOME/.maestro"; cp -R "$HOME/mz/maestro/." "$HOME/.maestro/"
  mi="version=$(limf 30 "$M" --version 2>/dev/null | grep -x -E '[0-9]+\.[0-9]+\.[0-9]+' | paste -sd, -) s=$(( $(date +%s) - t ))"; fi
fact maestro-install "$mi" "version=$MV"
case "$mi" in failed*) fact driver "skipped=no maestro" "cold=ok warm=ok"; exit 0;; esac
left() { local c="$1" l=$(( E - $(date +%s) )); [ "$l" -ge "$c" ] || c="$l"; [ "$c" -ge 0 ] || c=0; echo "$c"; }
t=$(date +%s); limf 140 xcrun simctl boot "$U" >/dev/null 2>&1 || true
b=0; LB=$(left 1310); if [ "$LB" -lt 10 ]; then b=142; else limf "$LB" xcrun simctl bootstatus "$U" -b >/dev/null 2>&1 || b=$?; fi
fact driver-boot "rc=$b s=$(( $(date +%s) - t ))" "rc=0"
if [ "$b" != 0 ]; then limf 30 xcrun simctl shutdown "$U" >/dev/null 2>&1 || true; fact driver "skipped=not booted" "cold=ok warm=ok"; exit 0; fi
hier() { # <key> <ceiling> <start wait>: one hierarchy under min(ceiling, seconds left); the start wait shrinks by the same



  local k="$1" t r=0 c LH W; LH=$(left "$2"); W=$(( $3 - $2 + LH ))
  if [ "$W" -lt 60 ]; then echo "rc=skip s=0 lines=0 classes=- limit=$LH wait=$W"; return; fi
  t=$(date +%s); MAESTRO_DRIVER_STARTUP_TIMEOUT="${W}000" limf "$LH" "$M" --device "$U" hierarchy --compact > "$R/$k.txt" 2>&1 < /dev/null || r=$?
  c=$(perl -ne 'print "$1\n" if /\b([A-Za-z]{2,40}(?:Exception|Error|Timeout|Failure|Unreachable))\b/' "$R/$k.txt" | awk '!s[$0]++ && ++n <= 3' | paste -sd, - || true)
  echo "rc=$r s=$(( $(date +%s) - t )) lines=$(wc -l < "$R/$k.txt" | tr -d ' ') classes=${c:--} limit=$LH wait=$W"; }
clean() { # the E section 27 clean-up, once: its lines as FACT lines
  limf 70 bash "$(dirname "$0")/cm-driver.sh" "$U" 2>/dev/null | while IFS= read -r x; do
    case "$x" in "driver clean-up "[1-3]"/3 "*) n="${x#driver clean-up }"; n="${n%%/*}"; fact "driver-clean-$n" "${x#driver clean-up ?/3 }" -;;
      "driver log: "*) fact driver-log "${x#driver log: }" -;; esac; done; }
to() { case "$1" in rc=142\ *|rc=skip\ *|*Timeout*) return 0;; esac; return 1; }
S="cold=fail warm=not-run"; v1=$(hier driver-cold 1100 993); fact driver-cold "$v1" "rc=0"
case "$v1" in
  rc=0\ *) v=$(hier driver-warm 640 540); fact driver-warm "$v" "rc=0"; case "$v" in rc=0\ *) S="cold=ok warm=ok";; *) S="cold=ok warm=fail";; esac;;
  *) clean; v2=$(hier driver-cold-again 1100 993); fact driver-cold-again "$v2" "rc=0"
    case "$v2" in rc=0\ *) S="cold=rescued warm=not-run"; fact driver-rescued "cold-again passed after the clean-up (counted apart from a pass; warm not measured)" -;;
      *) d=fail-x2; if to "$v1" && to "$v2"; then d=timeout-x2; fi; fact driver-start "$d" -;; esac;;
esac
limf 30 xcrun simctl shutdown "$U" >/dev/null 2>&1; fact driver-shutdown "rc=$?" "rc=0"
fact driver "$S" "cold=ok warm=ok"
exit 0
