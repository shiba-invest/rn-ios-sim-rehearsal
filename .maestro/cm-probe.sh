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

case "${CM_TAG:-}" in cm-stage1-*) echo "PROBE tag ok (cm-stage1-*)";; *) echo "PROBE STOP: CM_TAG is not cm-stage1-*, nothing read"; exit 0;; esac

GHT="${GH_STATUS_TOKEN:-}"; unset GH_STATUS_TOKEN

VL=ok; [ "${#E2E_0003_LOGIN}" -ge 3 ] 2>/dev/null || VL=short; [ "${#E2E_0003_PASSWORD}" -ge 4 ] 2>/dev/null || VL=short
fact value-lengths "id=$([ "${#E2E_0003_LOGIN}" -ge 3 ] && echo ok || echo short) pw=$([ "${#E2E_0003_PASSWORD}" -ge 4 ] && echo ok || echo short) token=$([ -n "$GHT" ] && echo set || echo empty)" "id=ok pw=ok token=set"


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


SJ="$P/sims.json"; limf 60 xcrun simctl list devices available -j > "$SJ" 2>/dev/null || true
fact sim-runtimes "$(node -e "try{console.log(Object.keys(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).devices).map(k=>k.split('.').pop()).join(' '))}catch(e){}" "$SJ")" "iOS-26-5"
fact iphone-17-pro-count "$(node -e "try{const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).devices['com.apple.CoreSimulator.SimRuntime.iOS-26-5']||[];console.log('n='+d.filter(x=>x.name==='iPhone 17 Pro'&&x.isAvailable!==false).length)}catch(e){}" "$SJ")" "n=1"
if limf 30 node .maestro/cm-pick.js < "$SJ" > "$P/sims.env" 2>"$P/pick.err"; then
  fact sim-pick "$(sed -n 's/^IPHONE_NAME=//p' "$P/sims.env") on $(sed -n 's/^SIM_RUNTIME=//p' "$P/sims.env" | sed 's/.*\.//')" "iPhone 17 Pro on iOS-26-5"
else fact sim-pick "failed: $(tr '\n' ' ' < "$P/pick.err")" "iPhone 17 Pro on iOS-26-5"; fi




fact memory "$(rd 20 'node -e "const o=require(\"os\");console.log(\"total_gb=\"+(o.totalmem()/2**30).toFixed(1)+\" free_gb=\"+(o.freemem()/2**30).toFixed(1)+\" cpus=\"+o.cpus().length)"')" "cpus=8"


fact proxy-env-names "$(env | sed -n 's/=.*//p' | grep -i -E '^(https?|all|no)_proxy$' | tr '\n' ' ')" -
fact cognito-post "$(rd 30 'bash .maestro/netcheck.sh "'"$P"'/net.txt" probe')" "http=400"
fact cognito-ip "$(rd 30 'curl -sS -o /dev/null --max-time 20 -w "ip=%{remote_ip} v=%{http_version}" https://cognito-idp.ap-northeast-1.amazonaws.com/')" -
CD=$(limf 30 curl -sS -o /dev/null -D - --max-time 20 https://cognito-idp.ap-northeast-1.amazonaws.com/ 2>/dev/null | sed -n 's/^[Dd]ate: //p' | tr -d '\r')
fact clock-skew-s "$(rd 10 'node -e "const d=Date.parse(process.argv[1]);console.log(isNaN(d)?\"no-date\":Math.round((Date.now()-d)/1000))" "'"$CD"'"')" -
for u in https://registry.npmjs.org/ https://cdn.cocoapods.org/ https://github.com/mobile-dev-inc/maestro/releases/download/cli-2.12.1/maestro.zip; do
  fact "reach-$(echo "$u" | sed 's#https://##; s#/.*##')" "$(rd 30 'curl -sS -o /dev/null -I -L --max-time 20 -w "http=%{http_code} all=%{time_total}" '"$u")" "http=200"
done



if [ "$VL" = ok ]; then fact cognito-auth "$(rd 30 'node .maestro/cm-auth.js')" "result=AuthenticationResult"
else fact cognito-auth "skipped=values-short (no sign-in tried)" "result=AuthenticationResult"; fi

fact gh-status "$(GH_STATUS_TOKEN="$GHT" rd 30 'node .maestro/cm-ghstatus.js codemagic/stage1-probe success "stage 1 probe ran (facts in the build log)"')" "http=201"




M=$(grep -c 'verdict=MATCH' "$F" || true); D=$(grep -c 'verdict=DIFF' "$F" || true); X=$(grep -c 'verdict=MISSING' "$F" || true)
echo "PROBE summary match=$M diff=$D missing=$X seconds=$(( $(date +%s) - T0 ))" | tee -a "$F"
exit 0
