#!/bin/bash
# Gate a: tools, simulator, memory, network from the host. Stops (non-zero) on anything missing.
# Also boots the iPhone early (like the reference order) and records the boot seconds.
set -eo pipefail
. ci/lib.sh
R="$OUT/gate-a.txt"
: > "$R"
fail() { echo "GATE-A FAIL: $*" | tee -a "$R"; exit 11; }
log() { echo "$*" | tee -a "$R"; }

log "macOS $(sw_vers -productVersion) build $(sw_vers -buildVersion)"
log "image ${ImageOS:-?} ${ImageVersion:-?}"
log "xcode-select $(xcode-select -p)  DEVELOPER_DIR=${DEVELOPER_DIR:-unset}"
xcodebuild -version | tr '\n' ' ' | sed 's/^/xcodebuild /' | tee -a "$R"; echo | tee -a "$R"
xcodebuild -version | grep -q "^Xcode ${WANT_XCODE}$" || fail "Xcode is not ${WANT_XCODE}"
log "node $(node -v)  npm $(npm -v)"
[ "$(node -v)" = "v${WANT_NODE}" ] || fail "node is not ${WANT_NODE}"
log "pod $(pod --version 2>/dev/null || echo missing)"
log "java $(java -version 2>&1 | head -1)"
log "cpu $(sysctl -n machdep.cpu.brand_string)  cores $(sysctl -n hw.ncpu)"
log "memory_bytes $(sysctl -n hw.memsize)"
log "disk $(df -h / | tail -1)"
if sudo -n true 2>/dev/null; then log "sudo yes"; else log "sudo no"; fi

# Simulator: the wanted runtime and device type must exist.
xcrun simctl list runtimes | tee "$OUT/sim-runtimes.txt" >/dev/null
grep -q "iOS ${WANT_IOS} " "$OUT/sim-runtimes.txt" || fail "runtime iOS ${WANT_IOS} missing"
UDID=$(bash ci/pick-sim.sh)
[ -n "$UDID" ] || fail "no ${WANT_DEVICE} on iOS ${WANT_IOS}"
log "sim ${WANT_DEVICE} iOS ${WANT_IOS} udid=$UDID"
echo "$UDID" > "$OUT/udid.txt"

# Network from the host: the auth endpoint answers 400 to an empty request; npm and the Maestro installer answer 200.
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -X POST \
  -H 'Content-Type: application/x-amz-json-1.1' -H 'X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth' \
  --data '{}' "https://cognito-idp.${AUTH_REGION}.amazonaws.com/") || true
log "net auth-endpoint http=$code"
[ "$code" = "400" ] || fail "auth endpoint http=$code (want 400)"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 https://registry.npmjs.org/expo) || true
log "net npm http=$code"; [ "$code" = "200" ] || fail "npm http=$code"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -L https://get.maestro.mobile.dev) || true
log "net maestro-installer http=$code"; [ "$code" = "200" ] || fail "maestro installer http=$code"

# Maestro, pinned.
export MAESTRO_VERSION="${WANT_MAESTRO}"
curl -fsSL https://get.maestro.mobile.dev | bash > "$OUT/maestro-install.txt" 2>&1 || fail "maestro install"
mv_ver=$("$HOME/.maestro/bin/maestro" --version 2>/dev/null | tail -1)
log "maestro $mv_ver"
[ "$mv_ver" = "${WANT_MAESTRO}" ] || fail "maestro is $mv_ver"
echo "$HOME/.maestro/bin" >> "${GITHUB_PATH:-/dev/null}"

# Boot early. Fault d-cold erases first (cold first boot); fault d-cap gives the boot a cap that is too short.
BOOT_CAP="${BOOT_CAP:-300}"
if [ "${FAULT:-none}" = "d-cold" ] || [ "${FAULT:-none}" = "d-cap" ]; then
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  xcrun simctl erase "$UDID"
  log "sim erased for fault ${FAULT}"
fi
[ "${FAULT:-none}" = "d-cap" ] && BOOT_CAP="${D_CAP_SECONDS:-5}"
xcrun simctl boot "$UDID" 2>/dev/null || true
timed sim-boot "$BOOT_CAP" xcrun simctl bootstatus "$UDID" -b > "$OUT/bootstatus.txt" 2>&1 || {
  log "sim boot did not finish within ${BOOT_CAP}s"; exit 12; }
log "sim boot seconds=$(awk -F'\t' '$1=="sim-boot"{print $2}' "$OUT/steps.tsv" | tail -1) cap=$BOOT_CAP"
log "GATE-A OK"
