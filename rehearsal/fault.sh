#!/bin/bash
# Practice faults only (not part of the mirrored flow). usage: fault.sh <pre-login|post-enter|pre-retry> <udid>
# FAULT: a = block the auth host at the login, restore 40 s after the Enter; b = block and never restore;
# a-look = as a, plus the app log and the screen words before the retry; look = the app log only (control);
# a-enter = as a-look, but the retry presses the password field then Enter (the first send's way);
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
applog() { xcrun simctl spawn "$UDID" log stream --style compact --level debug --predicate 'eventMessage CONTAINS "[REHEARSAL]"' 2>/dev/null \
  | sed -l -n 's/^[0-9-]* \([0-9:.]*\).*\(\[REHEARSAL\].*\)/\1 \2/p' > "$PWD/out/iphone/app-log.txt" & log "app log started"; }
words() { local h w n; h=$(maestro --device "$UDID" hierarchy 2>/dev/null)
  for w in "ログインできませんでした。通信環境をご確認ください" "ログインできませんでした。もう一度お試しください" "パスワードを確認しています…" "ログイン" "ホーム" "れんしゅう" "職員IDを入力してください" "パスワードを入力してください"; do
    n=$(printf '%s' "$h" | grep -o "\"$w\"" | wc -l | tr -d ' '); log "screen \"$w\"=$n"; done
  log "screen keyboard-lines=$(printf '%s' "$h" | grep -ci keyboard)";
  log "screen $(printf '%s' "$h" | node rehearsal/bounds.js)"; }
case "$FAULT:$P" in
  a:pre-login|b:pre-login|c-up:pre-login) block ;;
  a-look:pre-login|a-enter:pre-login) mkdir -p out/iphone; applog; block ;;
  look:pre-login) mkdir -p out/iphone; applog ;;
  a:post-enter|a-look:post-enter|a-enter:post-enter|c-up:post-enter) ( sleep 40; unblock ) > /dev/null 2>&1 & log "restore in 40 s" ;;
  a-look:pre-retry) words ;;
  a-enter:pre-retry) words; printf '%s
' 'appId: dev.rehearsal.sim' '---' '- tapOn:' '    text: "パスワード"' '    index: 1' '- pressKey: Enter' > .maestro/trial-retry.yaml; log "retry flow = password field then Enter" ;;
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
