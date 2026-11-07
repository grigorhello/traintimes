#!/usr/bin/env bash
# Builds the app and runs the unit, snapshot and UI tests on an iOS simulator (TT-101).
# Used by CI and runnable on any Mac with Xcode 16 or later: scripts/ci-test.sh
# Set SIMULATOR_NAME to pick a device (default: the newest "iPhone 16", else the newest iPhone).
set -euo pipefail
cd "$(dirname "$0")/.."

PREFERRED="${SIMULATOR_NAME:-iPhone 16}"
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
preferred = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
candidates = []
for runtime, entries in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for d in entries:
        if d["name"].startswith("iPhone"):
            candidates.append((d["name"] == preferred, version, d["name"], d["udid"]))
if not candidates:
    sys.exit("No iPhone simulator available")
candidates.sort(reverse=True)
print(candidates[0][3])
print("Simulator:", candidates[0][2], "iOS %d.%d" % candidates[0][1], file=sys.stderr)
' "$PREFERRED")

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
