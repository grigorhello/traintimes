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
# Not inside $(...) or <(...): macOS bash 3.2 misreads a heredoc there that holds a quote.
mkdir -p build
python3 - "$PREFERRED" "${SIMULATOR_OS:-}" > build/simulator.txt <<'PY'
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
# Some runtimes serve one new device only (iOS-27-2-iPhone19-4 in Xcode 27.2): take the newest that runs this device.
fits = [r for r in runtimes if any(t["name"] == preferred for t in r.get("supportedDeviceTypes", []))]
if not fits:
    names = sorted({t["name"] for r in runtimes for t in r.get("supportedDeviceTypes", []) if t["name"].startswith("iPhone")})
    sys.exit("No iOS %s runtime runs %s. Its iPhones: %s" % (wanted or "simulator", preferred, ", ".join(names)))
runtime = max(fits, key=key)
devices = [d for d in simctl("devices", "available")["devices"].get(runtime["identifier"], []) if d["name"] == preferred]
if devices:
    udid = devices[0]["udid"]
else:
    kind = next(t["identifier"] for t in runtime["supportedDeviceTypes"] if t["name"] == preferred)
    udid = subprocess.check_output(["xcrun", "simctl", "create", preferred, kind, runtime["identifier"]], text=True).strip()
    print("Created", preferred, "on iOS", runtime["version"], file=sys.stderr)
print("Simulator:", preferred, "iOS", runtime["version"], file=sys.stderr)
print(udid, runtime["version"])
PY
read -r UDID IOS_VERSION < build/simulator.txt
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
  2>&1 | tee build/xcodebuild.log | "${FORMATTER[@]}" || status=$?

# The formatter shows test results only, so a run that ends without them (the test app crashed or never started) left
# nothing to read in the log, and cloud sessions cannot download the result bundle. On a failure, print xcodebuild's own
# last lines, the result bundle's summary and the newest crash report of the app.
if [[ "${status:-0}" -ne 0 ]]; then
  echo "::group::xcodebuild's last lines"
  tail -n 150 build/xcodebuild.log
  echo "::endgroup::"
  echo "::group::Result bundle summary"
  xcrun xcresulttool get test-results summary --path "$RESULT" 2>&1 | head -c 20000 || true
  echo
  echo "::endgroup::"
  report=$(ls -t "$HOME"/Library/Logs/DiagnosticReports/TrainTimes*.ips 2>/dev/null | head -n 1 || true)
  if [[ -n "$report" ]]; then
    echo "::group::Crash report $report"
    head -c 12000 "$report"
    echo
    echo "::endgroup::"
  fi
  exit "$status"
fi
