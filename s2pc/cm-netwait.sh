#!/bin/bash







set -u
F="$1"; T="$2"; S=$(date +%s); n=0
. "$(dirname "$0")/cm-lim.sh"
while :; do
  n=$((n + 1)); r=0
  lim 115 bash "$(dirname "$0")/netcheck.sh" "$F" "$T-$n" >/dev/null 2>&1 || r=$?
  if [ "$r" = 0 ]; then echo "network reached before the login on try $n after $(( $(date +%s) - S )) s"; exit 0; fi
  if [ "$r" = 2 ]; then exit 3; fi
  lim 30 sleep 10 || true
done
