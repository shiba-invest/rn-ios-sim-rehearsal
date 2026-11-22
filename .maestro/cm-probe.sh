#!/bin/bash






set -u
CM_ROOT="$PWD"; . .maestro/cm-lim.sh
P="$PWD/out/probe"; mkdir -p "$P"; F="$P/facts.txt"; : > "$F"
T0=$(date +%s)
fact() { # <key> <value> <expect|-> : MATCH when value contains expect; "-" = record only
  local v="${2:-}"; local e="$3"; local r
  if [ -z "$v" ]; then r=MISSING; elif [ "$e" = "-" ]; then r=RECORD; else case "$v" in *"$e"*) r=MATCH;; *) r=DIFF;; esac; fi
  echo "FACT $1 value=$v expect=$e verdict=$r" | tee -a "$F"; }
rd() { limf "$1" bash -c "$2" 2>&1 | tr '\n' ' ' | sed 's/ *$//' || true; }
echo "PROBE start $(date -u +%Y-%m-%dT%H:%M:%SZ)"





TG="${CM_TAG:-}"; case "$TG" in cm-stage1-*) TAGOK=ok;; *) TAGOK=no;; esac

GHT="${GH_STATUS_TOKEN:-}"; unset GH_STATUS_TOKEN


ID="${E2E_0003_LOGIN:-}"; PW="${E2E_0003_PASSWORD:-}"
VL=ok; [ "${#ID}" -ge 3 ] || VL=short; [ "${#PW}" -ge 4 ] || VL=short
fact value-lengths "id=$([ "${#ID}" -ge 3 ] && echo ok || echo short) pw=$([ "${#PW}" -ge 4 ] && echo ok || echo short) token=$([ -n "$GHT" ] && echo set || echo empty)" "id=ok pw=ok token=set"
unset ID PW
fact tag "${TG:-unset}" "cm-stage1-"
fact cm-names "$(compgen -e | grep -E '^CM_' | sort | tr '\n' ' ')" -


fact macos "$(rd 20 'sw_vers -productVersion; sw_vers -buildVersion')" -
fact xcode "$(rd 30 'xcodebuild -version | grep -E "^Xcode [0-9]"')" "Xcode 26.6"
fact xcode-path "$(rd 20 'xcode-select -p')" "Xcode-26.6.app"
fact node "$(rd 20 'node -v')" "v24.17.0"
fact npm "$(rd 20 'npm -v')" -
fact pod "$(rd 30 'pod --version')" "1.16.2"
fact bash "$(rd 10 '/bin/bash --version | grep -E "^GNU bash"')" "3.2"
fact perl "$(rd 10 'perl -e "print \$^V"')" "v5"
fact curl "$(rd 10 'curl --version | grep -E "^curl [0-9]"')" -
fact java "$(rd 20 'java -version 2>&1 | grep -E "^(openjdk|java) version"')" 'version "17.'


SJ="$P/sims.json"; limf 270 xcrun simctl list devices available -j > "$SJ" 2>/dev/null || true
fact sim-runtimes "$(limf 20 node .maestro/cm-probe-read.js runtimes "$SJ" 2>&1)" "iOS-26-5"
fact iphone-17-pro-count "$(limf 20 node .maestro/cm-probe-read.js count "$SJ" 2>&1)" "n=1"
if limf 30 node .maestro/cm-pick.js < "$SJ" > "$P/sims.env" 2>"$P/pick.err"; then
  fact sim-pick "$(sed -n 's/^IPHONE_NAME=//p' "$P/sims.env") on $(sed -n 's/^SIM_RUNTIME=//p' "$P/sims.env" | sed 's/.*\.//')" "iPhone 17 Pro on iOS-26-5"
else fact sim-pick "failed: $(tr '\n' ' ' < "$P/pick.err")" "iPhone 17 Pro on iOS-26-5"; fi




fact memory "$(rd 20 'node .maestro/cm-probe-read.js memory')" "cpus=8"


PX=$(env | sed -n 's/=.*//p' | grep -i -E '^(https?|all|no)_proxy$' | tr '\n' ' '); fact proxy-env-names "${PX:-none}" -
fact cognito-post "$(rd 30 'bash .maestro/netcheck.sh "'"$P"'/net.txt" probe')" "http=400"
fact cognito-ip "$(rd 30 'curl -sS -o /dev/null --max-time 20 -w "ip=%{remote_ip} v=%{http_version}" https://cognito-idp.ap-northeast-1.amazonaws.com/')" -
CD=$(limf 30 curl -sS -o /dev/null -D - --max-time 20 https://cognito-idp.ap-northeast-1.amazonaws.com/ 2>/dev/null | sed -n 's/^[Dd]ate: //p' | tr -d '\r')
fact clock-skew-s "$(rd 10 'node .maestro/cm-probe-read.js skew "'"$CD"'"')" -
for u in https://registry.npmjs.org/ https://cdn.cocoapods.org/ https://github.com/mobile-dev-inc/maestro/releases/download/cli-2.12.1/maestro.zip; do
  fact "reach-$(echo "$u" | sed 's#https://##; s#/.*##')" "$(rd 30 'curl -sS -o /dev/null -I -L --max-time 20 -w "http=%{http_code} all=%{time_total}" '"$u")" "http=200"
done



if [ "$TAGOK" != ok ]; then fact cognito-auth "skipped=tag-not-cm-stage1 (no sign-in tried)" "result=AuthenticationResult"
elif [ "$VL" = ok ]; then fact cognito-auth "$(rd 60 'node .maestro/cm-auth.js "'"$P"'/list.txt"')" "result=AuthenticationResult"
else fact cognito-auth "skipped=values-short (no sign-in tried)" "result=AuthenticationResult"; fi




GD=$(sed -n 's/^list-data //p' "$P/list.txt" 2>/dev/null | tr -cd 'A-Za-z0-9=:,/()._ -')
fact list-data "${GD:-skipped=no-sign-in (see cognito-auth)}" -

if [ "$TAGOK" = ok ]; then fact gh-status "$(GH_STATUS_TOKEN="$GHT" rd 30 'node .maestro/cm-ghstatus.js codemagic/stage1-probe success "stage 1 probe ran (facts in the build log)"')" "http=201"
else fact gh-status "skipped=tag-not-cm-stage1 (no status written)" "http=201"; fi




M=$(grep -c 'verdict=MATCH' "$F" || true); D=$(grep -c 'verdict=DIFF' "$F" || true); X=$(grep -c 'verdict=MISSING' "$F" || true)
echo "PROBE summary match=$M diff=$D missing=$X seconds=$(( $(date +%s) - T0 ))" | tee -a "$F"





GH_STATUS_TOKEN="$GHT" limf 70 node .maestro/cm-facts-status.js "$F" 2>&1 | tee "$P/facts-status.txt" || true
exit 0
