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
print(udid, runtime["version"], runtime.get("buildversion") or "-", runtime["identifier"])
PY
read -r UDID IOS_VERSION IOS_BUILD RUNTIME_ID < build/simulator.txt
[[ -n "${GITHUB_ENV:-}" ]] && echo "SIMULATOR_RUNTIME=iOS $IOS_VERSION" >> "$GITHUB_ENV"

# The runtime's image kind and mount path as `simctl runtime list -v` shows them ("kind|mount", empty if not listed).
runtime_mount() {
  xcrun simctl runtime list -v 2>/dev/null | awk -v build="($IOS_BUILD)" '
    /^[^ \t]/ { here = index($0, build) > 0; next }
    here && /Image Kind:/ { sub(/^[ \t]*Image Kind:[ \t]*/, ""); kind = $0 }
    here && /Mount Path:/ { sub(/^[ \t]*Mount Path:[ \t]*/, ""); print kind "|" $0; exit }' || true
}

# TT-260: the iOS 26.5 runtime CI downloads is a "Patchable Cryptex Disk Image". It is first mounted under
# /Library/Developer/CoreSimulator/Volumes; some minutes after the first boot the host builds its dyld shared cache and
# remounts it as a cryptex, and whatever runs on it dies: "Invalid device state" (Mach error -308) at the test host's
# launch, then "Unable to boot device because we cannot determine the runtime bundle" with the device's runtime nil.
# Every run of Nov 27-28 lost the simulator so on its first attempt; the retry passed only where the remount was over.
runtime_pending() {
  local state
  state=$(runtime_mount)
  [[ "$state" == *Patchable*"|/Library/Developer/CoreSimulator/Volumes/"* ]]
}

# Boots the simulator and waits until it is ready, first-boot data migration included, for 10 min at most.
boot_simulator() {
  perl -e 'alarm shift; exec @ARGV' 600 xcrun simctl bootstatus "$UDID" -b > build/bootstatus.log 2>&1 && return 0
  tail -n 5 build/bootstatus.log
  return 1
}

# Before each test attempt: have the runtime remounted with no device on it, then boot the simulator and wait for it,
# so xcodebuild neither boots it during the build nor launches the test host on a device that is still migrating.
settle_simulator() {
  echo "::group::Settle the simulator"
  echo "iOS $IOS_VERSION ($IOS_BUILD): $(runtime_mount)"
  if runtime_pending; then
    # Build the dyld shared cache now, 15 min at most. Which identifier simctl takes is not documented, so each is tried.
    xcrun simctl help runtime 2>&1 | grep -i -A3 dyld || true
    for id in "$RUNTIME_ID" "$IOS_BUILD"; do
      if time perl -e 'alarm shift; exec @ARGV' 900 xcrun simctl runtime dyld_shared_cache update "$id"; then break; fi
    done
    echo "After the dyld shared cache: $(runtime_mount)"
  fi
  if runtime_pending; then
    # Still not remounted: boot once so the host starts on the cache, shut down, and wait for the remount, 8 min at most.
    boot_simulator || true
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    for _ in $(seq 1 32); do
      runtime_pending || break
      sleep 15
    done
    echo "After waiting: $(runtime_mount)"
    runtime_pending && echo "::warning::iOS $IOS_VERSION is still mounted under /Library/Developer/CoreSimulator/Volumes; the tests may lose the simulator."
  fi
  if ! boot_simulator; then
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    boot_simulator || echo "::warning::The simulator did not finish booting."
  fi
  tail -n 2 build/bootstatus.log
  echo "Booted on: $(runtime_mount)"
  echo "::endgroup::"
}

xcodebuild -version
RESULT=build/TestResults.xcresult

FORMATTER=(cat)
if command -v xcbeautify >/dev/null 2>&1; then
  FORMATTER=(xcbeautify)
  [[ -n "${GITHUB_ACTIONS:-}" ]] && FORMATTER+=(--renderer github-actions)
fi

run_tests() {
  rm -rf "$RESULT"
  status=0
  xcodebuild test \
    -project TrainTimes.xcodeproj \
    -scheme TrainTimes \
    -configuration Debug \
    -destination "id=$UDID" \
    -resultBundlePath "$RESULT" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    -test-timeouts-enabled YES \
    2>&1 | tee build/xcodebuild.log | "${FORMATTER[@]}" || status=$?
}

# A test that hangs fails after 10 min (xcodebuild's default allowance once timeouts are on) instead of running the job
# into its 90 min limit, which cancels the step before anything below can say which test it was.
settle_simulator
run_tests

# On the Xcode 27 image the simulator itself sometimes fails under the tests: its service dies while the test runner is
# installed ("Invalid device state", Mach error -308), or the test host is killed mid-run and the iOS runtime then reads as
# "(null)" ("cannot determine the runtime bundle"). Seen on most TT-243 runs and on main after TT-241 and TT-242, with no
# test at fault. Then restart the simulator service, settle the simulator again (above) and run the tests once more; the
# build is done, so the second run costs the tests only. A real test failure fails the second run too.
SIMULATOR_LOST='Failed to install or launch the test runner|Invalid device state|cannot determine the runtime bundle|Unable to boot device'
if [[ "$status" -ne 0 ]] && grep -qE "$SIMULATOR_LOST" build/xcodebuild.log; then
  echo "::warning::The simulator failed under the tests ($(grep -oE "$SIMULATOR_LOST" build/xcodebuild.log | head -n 1)); restarting it and running the tests again."
  # The disk and the runtime's state before the restart (settle_simulator logs its mount after), so a run that loses the
  # simulator shows why: on PR #266 the runtime was listed after the restart twice in a row, and xcodebuild still read it
  # as "(null)"; on PR #271 it was still mounted under /Library/Developer/CoreSimulator/Volumes (TT-260).
  echo "::group::Simulator state before the restart"
  grep -nE "$SIMULATOR_LOST" build/xcodebuild.log | head -n 5 | cut -c1-400 || true
  df -h / /System/Volumes/Data 2>/dev/null || true
  xcrun simctl runtime list -v 2>&1 | head -n 80 || true
  echo "::endgroup::"
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
  xcrun simctl list runtimes available | grep "iOS $IOS_VERSION" || echo "::warning::iOS $IOS_VERSION is not listed after the restart."
  settle_simulator
  cp build/xcodebuild.log build/xcodebuild-first.log
  run_tests
fi

# The formatter shows test results only, so a run that ends without them (the test app crashed or never started) left
# nothing to read in the log, and cloud sessions cannot download the result bundle. On a failure, print xcodebuild's own
# last lines, the result bundle's summary and the newest crash report of the app.
if [[ "$status" -ne 0 ]]; then
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
    # The report is a JSON header line and a JSON body; print the exception and the stacks by name (the main thread and
    # the crashed one in full, the first frames of the rest), since a hung test's abort only shows where in these.
    python3 - "$report" <<'PY' || head -c 12000 "$report"
import json, sys
text = open(sys.argv[1]).read()
body = json.loads(text[text.index("\n") + 1:])
images = body.get("usedImages", [])
print(body.get("exception"), body.get("termination", {}).get("indicator"))
faulting = body.get("faultingThread", 0)
for index, thread in enumerate(body.get("threads", [])):
    full = index in (0, faulting)
    print("Thread", index, thread.get("name", thread.get("queue", "")), "(crashed)" if index == faulting else "")
    for frame in thread.get("frames", [])[: 60 if full else 8]:
        image = frame.get("imageIndex")
        name = images[image].get("name", "?") if image is not None and image < len(images) else "?"
        print("   ", name, frame.get("symbol", hex(frame.get("imageOffset", 0))))
PY
    echo
    echo "::endgroup::"
  fi
  exit "$status"
fi
