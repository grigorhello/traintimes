#!/usr/bin/env bash
# Builds the app and runs the unit, snapshot and UI tests on an iOS simulator (TT-101).
# Used by CI and runnable on any Mac with Xcode 26 or later: scripts/ci-test.sh
# The tests run on an "iPhone 17 Pro" simulator (D23; SIMULATOR_NAME picks another device) on the newest iOS runtime
# installed, or on the iOS version in SIMULATOR_OS (for example 26.5). When that runtime has no such device, one is
# created: GitHub's Xcode 27 image ships none (TT-241).
set -euo pipefail
cd "$(dirname "$0")/.."

# D17/D24: every time goes through the one formatter, Shared/TimeFormatter.swift (in Shared/ since TT-182).
if grep -rnE 'DateFormatter|\.formatted\(' Sources Shared Widgets --include='*.swift' | grep -v '^Shared/TimeFormatter.swift:'; then
  echo "::error::DateFormatter or Date.formatted used outside Shared/TimeFormatter.swift (D17)"
  exit 1
fi

PREFERRED="${SIMULATOR_NAME:-iPhone 17 Pro}"
read -r UDID IOS_VERSION < <(python3 - "$PREFERRED" "${SIMULATOR_OS:-}" <<'PY'
import json, subprocess, sys
preferred, wanted = sys.argv[1], sys.argv[2]
def simctl(*args):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j", *args]))
def key(runtime):
    return tuple(int(part) for part in runtime["version"].split("."))
runtimes = [r for r in simctl("runtimes", "available")["runtimes"] if r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
if wanted:
    runtimes = [r for r in runtimes if r["version"] == wanted or r["version"].startswith(wanted + ".")]
if not runtimes:
    sys.exit("No iOS %s simulator runtime installed" % wanted)
runtime = max(runtimes, key=key)
devices = [d for d in simctl("devices", "available")["devices"].get(runtime["identifier"], []) if d["name"] == preferred]
if devices:
    udid = devices[0]["udid"]
else:
    kinds = [t["identifier"] for t in runtime.get("supportedDeviceTypes", []) if t["name"] == preferred]
    if not kinds:
        sys.exit("iOS %s has no %s device type" % (runtime["version"], preferred))
    udid = subprocess.check_output(["xcrun", "simctl", "create", preferred, kinds[0], runtime["identifier"]], text=True).strip()
    print("Created", preferred, "on iOS", runtime["version"], file=sys.stderr)
print("Simulator:", preferred, "iOS", runtime["version"], file=sys.stderr)
print(udid, runtime["version"])
PY
)
[[ -n "${GITHUB_ENV:-}" ]] && echo "SIMULATOR_RUNTIME=iOS $IOS_VERSION" >> "$GITHUB_ENV"

xcodebuild -version
RESULT=build/TestResults.xcresult
rm -rf "$RESULT"

FORMATTER=(cat)
if command -v xcbeautify >/dev/null 2>&1; then
  FORMATTER=(xcbeautify)
  [[ -n "${GITHUB_ACTIONS:-}" ]] && FORMATTER+=(--renderer github-actions)
fi

xcodebuild test \
  -project TrainTimes.xcodeproj \
  -scheme TrainTimes \
  -configuration Debug \
  -destination "id=$UDID" \
  -resultBundlePath "$RESULT" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  2>&1 | "${FORMATTER[@]}"
