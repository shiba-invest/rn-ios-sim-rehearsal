#!/bin/bash
# Prints the UDID of WANT_DEVICE on iOS WANT_IOS; creates one if the image has none.
set -eo pipefail
rt="com.apple.CoreSimulator.SimRuntime.iOS-${WANT_IOS//./-}"
udid=$(xcrun simctl list devices -j | node -e '
  const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
  const list = j.devices[process.argv[1]] || [];
  const d = list.find((x) => x.name === process.argv[2] && x.isAvailable);
  process.stdout.write(d ? d.udid : "");
' "$rt" "$WANT_DEVICE")
if [ -z "$udid" ]; then
  dt="com.apple.CoreSimulator.SimDeviceType.${WANT_DEVICE// /-}"
  udid=$(xcrun simctl create "$WANT_DEVICE" "$dt" "$rt")
fi
echo "$udid"
