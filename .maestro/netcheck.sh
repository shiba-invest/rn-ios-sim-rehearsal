#!/bin/bash




set -u
F="$1"; T="$2"
mkdir -p "$(dirname "$F")"
W=$(curl -sS -o /dev/null --max-time 20 -X POST https://cognito-idp.ap-northeast-1.amazonaws.com/ \
  -H 'Content-Type: application/x-amz-json-1.1' \
  -w 'http=%{http_code} dns=%{time_namelookup} tcp=%{time_connect} tls=%{time_appconnect} all=%{time_total}' 2>&1)
L="$(date -u +%H:%M:%S) $T $(echo "$W" | tr '\n' ' ')"
echo "$L" | tee -a "$F"
case "$W" in *http=000*|"") exit 1;; esac
exit 0
