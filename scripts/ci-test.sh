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

# The runtime's image kind and mount path as `simctl runtime list -v` shows them ("kind|mount"; "kind|" when it is listed
# with no mount path, empty when it is not listed or simctl does not answer within 2 min).
runtime_mount() {
  perl -e 'alarm shift; exec @ARGV' 120 xcrun simctl runtime list -v 2>/dev/null | awk -v build="($IOS_BUILD)" '
    /^[^ \t]/ { here = index($0, build) > 0; next }
    here && /Image Kind:/ { sub(/^[ \t]*Image Kind:[ \t]*/, ""); kind = $0 }
    here && /Mount Path:/ { sub(/^[ \t]*Mount Path:[ \t]*/, ""); print kind "|" $0; done = 1; exit }
    END { if (kind != "" && !done) print kind "|" }' || true
}

# TT-260: the iOS 26.5 runtime CI downloads is a "Patchable Cryptex Disk Image" that comes without its dyld shared
# cache. The first boot builds it (9.5 min on run 686), and meanwhile the runtime moves between its cryptex mount
# (/private/var/run/com.apple.security.cryptexd/mnt) and /Library/Developer/CoreSimulator/Volumes, killing whatever runs
# on it: "Invalid device state" (Mach error -308) at the test host's launch, "Unable to boot device because we cannot
# determine the runtime bundle", or the UI test runner's SIGTERM "while preparing to run tests". Every run of Nov 27-28
# lost the simulator so; the retry passed only where the runtime was back on its cryptex mount for good. So the script
# builds the cache first (`simctl runtime dyld_shared_cache update`, which returns once it is built), in the background
# while the app builds, then waits for the runtime to stay on its cryptex mount, then boots the simulator.
start_cache_build() {
  [[ -e build/runtime-settled ]] && return 0
  touch build/runtime-settled
  echo "iOS $IOS_VERSION ($IOS_BUILD) before the dyld shared cache: $(note_mount)"
  (
    started=$(date +%s)
    rc=0
    perl -e 'alarm shift; exec @ARGV' 1500 xcrun simctl runtime dyld_shared_cache update "$RUNTIME_ID" || rc=$?
    echo "dyld_shared_cache update $RUNTIME_ID: exit $rc after $(( $(date +%s) - started )) s"
  ) > build/dyld-cache.log 2>&1 &
  CACHE_PID=$!
}

# Prints the runtime's mount and keeps it in build/runtime-mount.txt; a mount unlike the last one seen is noted as a move
# in build/runtime-moved.txt.
note_mount() {
  local now last
  now=$(runtime_mount)
  last=$(cat build/runtime-mount.txt 2>/dev/null || true)
  if [[ "$now" != "$last" ]]; then
    [[ -e build/runtime-mount.txt ]] && echo "$now" >> build/runtime-moved.txt
    echo "$now" > build/runtime-mount.txt
  fi
  echo "$now"
}

# Waits, 10 min at most, until the runtime has been on its cryptex mount for 30 s. When it moved since it was last seen
# (before the cache build, or at the last settle), restarts the simulator service so it reads the runtime from there.
wait_for_mount() {
  local now last steady=0
  last=$(cat build/runtime-mount.txt 2>/dev/null || true)
  for _ in $(seq 1 60); do
    now=$(note_mount)
    [[ "$now" != "$last" ]] && echo "Runtime moved: $now"
    last=$now
    if [[ "$now" == *"|/private/var/run/com.apple.security.cryptexd/"* ]]; then
      steady=$((steady + 1))
      [[ "$steady" -ge 3 ]] && break
    else
      steady=0
    fi
    sleep 10
  done
  [[ "$steady" -ge 3 ]] || echo "::warning::iOS $IOS_VERSION did not settle on its cryptex mount ($last); the tests may lose the simulator."
  if [[ -s build/runtime-moved.txt ]]; then
    : > build/runtime-moved.txt
    xcrun simctl shutdown all >/dev/null 2>&1 || true
    killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
    xcrun simctl list runtimes available | grep "iOS $IOS_VERSION" || echo "::warning::iOS $IOS_VERSION is not listed after the move."
  fi
}

# Boots the simulator and waits until it is ready, data migration included, 15 min at most. bootstatus exits 0 even
# when the boot ends in "Data Migration Failed", so the log must say it finished (or that the device was up already).
boot_simulator() {
  local rc=0
  perl -e 'alarm shift; exec @ARGV' 900 xcrun simctl bootstatus "$UDID" -b > build/bootstatus.log 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] && grep -qiE 'Finished|already booted' build/bootstatus.log && ! grep -qi 'Migration Failed' build/bootstatus.log && return 0
  echo "bootstatus exit $rc:"
  tail -n 5 build/bootstatus.log
  return 1
}

# Before each test attempt: let the cache build finish, wait for the runtime to settle, then boot the simulator and wait
# for it, so the tests never start on a device the runtime's move can kill.
settle_simulator() {
  echo "::group::Settle the simulator"
  echo "iOS $IOS_VERSION ($IOS_BUILD): $(note_mount)"
  if [[ -n "${CACHE_PID:-}" ]]; then
    wait "$CACHE_PID" || true
    CACHE_PID=
    cat build/dyld-cache.log
    echo "After the dyld shared cache: $(note_mount)"
  fi
  wait_for_mount
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

# The build and the tests are two xcodebuild runs, so the simulator is settled between them while nothing runs on it.
build_tests() {
  status=0
  xcodebuild build-for-testing \
    -project TrainTimes.xcodeproj \
    -scheme TrainTimes \
    -configuration Debug \
    -destination "id=$UDID" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    2>&1 | tee build/xcodebuild.log | "${FORMATTER[@]}" || status=$?
}

# A test that hangs fails after 10 min (xcodebuild's default allowance once timeouts are on) instead of running the job
# into its 90 min limit, which cancels the step before anything below can say which test it was.
run_tests() {
  rm -rf "$RESULT"
  status=0
  xcodebuild test-without-building \
    -project TrainTimes.xcodeproj \
    -scheme TrainTimes \
    -configuration Debug \
    -destination "id=$UDID" \
    -resultBundlePath "$RESULT" \
    -test-timeouts-enabled YES \
    2>&1 | tee build/xcodebuild.log | "${FORMATTER[@]}" || status=$?
}

start_cache_build
build_tests
if [[ "$status" -eq 0 ]]; then
  settle_simulator
  run_tests
fi

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
