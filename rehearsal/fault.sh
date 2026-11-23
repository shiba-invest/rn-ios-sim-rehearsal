#!/bin/bash
# Practice faults only (not part of the mirrored flow). usage: fault.sh <pre-login|post-enter|pre-retry> <udid>
# FAULT: a = block the auth host at the login, restore 40 s after the Enter; b = block and never restore;
# a-look = as a, plus the app log and the screen words before the retry; look = the app log only (control);
# a-enter = as a-look, but the retry presses the password field then Enter (the first send's way);
# a-look, a-enter and look also keep the Maestro step kinds and results (rehearsal/steps.js, no arguments) every 10 s;
# gate-up = block at the login, restore after 90 s (head 2d: the net gate waits, then the first send reaches home);
# gate-up-500 = as gate-up, restore after 500 s (near the 600 s gate end); post-in = no block before the login,
# block once the 2nd inputText (password) of the login flow is COMPLETED, restore 40 s after the Enter (the retry way);
# look-old = look on the older password row (rehearsal/index-old.tsx copied over app/index.tsx before the build);
# post-in blocks before the login (the focus trigger lost the race: submit comes 4 s after the focus) and restores 40 s after the Enter; post-in retries by the masked text (tapOn text "•+" then Enter); post-in-left = same, but tapOn leftOf "パスワードを表示";
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
stepwatch() { ( D="$HOME/cm-maestro-raw/iphone"; O="$PWD/out/iphone/steps.txt"; t=0; while [ $t -lt 3600 ]; do
    for c in "$D"/m-*.console; do [ -f "$c" ] || continue; b=$(basename "$c" .console); k="$PWD/out/iphone/.n-$b"
      node rehearsal/steps.js "$c" "$(cat "$k" 2>/dev/null || echo 0)" 2> "$k.new" | sed "s/^/$(date -u +%H:%M:%S) $b /" >> "$O"; mv "$k.new" "$k"; done
    sleep 10; t=$((t + 10)); done ) > /dev/null 2>&1 & log "step watch started (kinds and results only, every 10 s)"; }
postin() { ( O="$PWD/out/iphone/app-log.txt"; t=0; while [ $t -lt 3600 ]; do
    grep -q "pw focus" "$O" 2>/dev/null && { log "post-in: password field focus seen in the app log"; block; exit 0; }
    sleep 0.5; t=$((t + 1)); done; log "post-in: password focus never seen, no block" ) & log "post-in watch started (app log, pw focus)"; }
syslog() { xcrun simctl spawn "$UDID" log stream --style compact --predicate 'process CONTAINS[c] "AutoFill" OR process CONTAINS[c] "passwordbreach" OR process CONTAINS[c] "SharedWebCredential" OR subsystem CONTAINS[c] "AuthenticationServices" OR eventMessage CONTAINS[c] "savePassword"' 2>/dev/null \
  | sed -l -n 's/^[0-9-]* \([0-9:]*\)[.0-9]* *[A-Za-z]* *\([A-Za-z]*\)\[.*/\1 \2/p' > "$PWD/out/iphone/sys-pw.txt" & log "password prompt process log started (time and process name only)"; }
# zs-hold = a listener on 127.0.0.1:22087 started just before home-first, named like a stale xcodebuild of this UDID so that
# the clean (pkill -f "xcodebuild test-without-building.*UDID") removes it; zs-hold-noclean = same, ZS_CLEAN=0 (control).
hold() { nohup perl -MIO::Socket::INET -e 'my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 22087, Listen => 5, ReuseAddr => 1) or exit 1; while (my $c = $s->accept) { push @k, $c; }' \n  xcodebuild test-without-building "$UDID" > /dev/null 2>&1 & sleep 2; log "hold started port22087-listen=$(lsof -nP -iTCP:22087 -sTCP:LISTEN 2>/dev/null | grep -c LISTEN)"; }
case "$FAULT:$P" in
  a:pre-login|b:pre-login|c-up:pre-login) block ;;
  a-look:pre-login|a-enter:pre-login) mkdir -p out/iphone; stepwatch; applog; block ;;
  gate-up:pre-login|gate-up-500:pre-login) mkdir -p out/iphone; stepwatch; applog; block
    s=90; [ "$FAULT" = gate-up-500 ] && s=500; ( sleep $s; unblock ) > /dev/null 2>&1 & log "restore in $s s" ;;
  post-in:pre-login|post-in-left:pre-login) mkdir -p out/iphone; stepwatch; applog; syslog; block ;;
  post-in:post-enter|post-in-left:post-enter) ( sleep 40; unblock ) > /dev/null 2>&1 & log "restore in 40 s" ;;
  post-in:pre-retry) words; printf '%s
' 'appId: dev.rehearsal.sim' '---' '- tapOn:' '    text: "•+"' '- pressKey: Enter' > .maestro/trial-retry.yaml; log "retry flow = masked text then Enter" ;;
  post-in-left:pre-retry) words; printf '%s
' 'appId: dev.rehearsal.sim' '---' '- tapOn:' '    leftOf: "パスワードを表示"' '- pressKey: Enter' > .maestro/trial-retry.yaml; log "retry flow = leftOf the eye button then Enter" ;;
  zs-hold:pre-login|zs-hold-noclean:pre-login) mkdir -p out/iphone; stepwatch; applog ;;
  zs-hold:pre-home|zs-hold-noclean:pre-home) hold ;;
  dst993:pre-login) mkdir -p out/iphone; stepwatch; applog ;;
  look:pre-login|look-old:pre-login|pwaf:pre-login|pwaf-ctl:pre-login) mkdir -p out/iphone; stepwatch; applog; syslog ;;
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
