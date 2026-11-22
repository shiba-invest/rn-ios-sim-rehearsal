#!/bin/bash
# Practice faults only (not part of the mirrored flow). usage: fault.sh <pre-login|post-enter|pre-retry> <udid>
# FAULT: a = block the auth host at the login, restore 40 s after the Enter; b = block and never restore;
# c-up = as a, plus the keyboard up on the password field before the resubmit; e = plant the practice values in out/.
P="$1"; UDID="$2"; HOST="cognito-idp.${AUTH_REGION}.amazonaws.com"; BH=192.0.2.1; F="$PWD/out/fault.txt"
mkdir -p "$PWD/out"; log() { echo "$(date -u +%H:%M:%S) fault=$FAULT $P $*" | tee -a "$F"; }
flushdns() { sudo dscacheutil -flushcache 2>/dev/null || true; sudo killall -HUP mDNSResponder 2>/dev/null || true; }
check() { curl -s -o /dev/null -w '%{http_code}' --max-time "$1" -X POST -H 'Content-Type: application/x-amz-json-1.1' "https://$HOST/" || true; }
block() { sudo sh -c "echo '$BH $HOST' >> /etc/hosts"
  echo "block drop out quick inet from any to $BH" | sudo pfctl -a com.apple/rehearsal -f - >/dev/null 2>&1 || true
  sudo pfctl -E >/dev/null 2>&1 || true; flushdns; log "blocked host-check http=$(check 8)"; }
unblock() { sudo sed -i '' "/$BH $HOST/d" /etc/hosts; sudo pfctl -a com.apple/rehearsal -F rules >/dev/null 2>&1 || true
  flushdns; log "restored host-check http=$(check 15)"; }
case "$FAULT:$P" in
  a:pre-login|b:pre-login|c-up:pre-login) block ;;
  a:post-enter|c-up:post-enter) ( sleep 40; unblock ) > /dev/null 2>&1 & log "restore in 40 s" ;;
  c-up:pre-retry) maestro --device "$UDID" test rehearsal/keyboard-up.yaml > /dev/null 2>&1; log "keyboard-up rc=$?" ;;
  e:post-enter)
    mkdir -p out/iphone
    printf 'typed %s and id %s\n' "$LOGIN_PW" "$LOGIN_ID" > out/iphone/planted.txt
    printf '{"inputText":%s}\n' "$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$LOGIN_PW")" > out/iphone/planted.json
    printf 'PNG-bytes %s\n' "$LOGIN_PW" > out/iphone/planted.png
    log "planted 3 files (txt, json, png)" ;;
  *) : ;;
esac
exit 0
