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
# cache, and it does not stay where it is first mounted. On every run of Nov 27-28 it moved about 8 to 10 min after the
# download, from its cryptex mount (/private/var/run/com.apple.security.cryptexd/mnt) to
# /Library/Developer/CoreSimulator/Volumes, and later (up to 22 min after the download) back to a cryptex mount, where it
# then stayed. Each move kills or hides the device: "Invalid device state" (Mach error -308) at the test host's launch,
# "Unable to boot device because we cannot determine the runtime bundle", the UI test runner's SIGTERM "while preparing
# to run tests", or "Unable to find a device matching the provided destination specifier" (run 689). Retries passed only
# where the runtime was back on its cryptex mount for good. So the script builds the cache first, in the background
# while the app builds (`simctl runtime dyld_shared_cache update`, which returns once it is built: 140 s on run 689,
# after which the first boot took 2 min instead of 9.5), then waits for the moves to be over before it boots.
start_cache_build() {
  [[ -e build/runtime-settled ]] && return 0
  touch build/runtime-settled
  runtime_place > build/runtime-place.txt
  echo "iOS $IOS_VERSION ($IOS_BUILD) before the dyld shared cache: $(runtime_mount); mounted as $(cat build/runtime-place.txt)"
  (
    started=$(date +%s)
    rc=0
    perl -e 'alarm shift; exec @ARGV' 1500 xcrun simctl runtime dyld_shared_cache update "$RUNTIME_ID" || rc=$?
    echo "dyld_shared_cache update $RUNTIME_ID: exit $rc after $(( $(date +%s) - started )) s"
  ) > build/dyld-cache.log 2>&1 &
  CACHE_PID=$!
}

# Where the runtime is mounted, from mount(8) (the disk too, so a remount at the same path counts as a move); simctl's
# mount path when mount(8) does not show it.
runtime_place() {
  local place
  place=$(mount | awk -v name="/iOS_$IOS_BUILD" 'substr($3, length($3) - length(name) + 1) == name { printf "%s %s; ", $1, $3 }')
  [[ -n "$place" ]] && echo "$place" || echo "simctl: $(runtime_mount)"
}

# Waits until the runtime has stayed on its cryptex mount for 60 s after its move (and 10 min after the download at the
# least, since the first move came 8 to 10 min after it), or, with no move by 15 min after the download, after that;
# never later than 32 min after the download. SIMULATOR_RUNTIME_INSTALLED_AT is set by the
# workflow when it downloaded the runtime; without it (a runtime that came with the image, or a Mac) nothing moves and
# nothing is awaited. Restarts the simulator service after a move, so that it reads the runtime from where it is now.
wait_for_runtime() {
  local installed=${SIMULATOR_RUNTIME_INSTALLED_AT:-} last now age steady=0 moved=false
  last=$(cat build/runtime-place.txt 2>/dev/null || true)
  now=$(runtime_place)
  if [[ -n "$last" && "$now" != "$last" ]]; then
    moved=true
    echo "Runtime moved since it was last seen: $now"
  fi
  last=$now
  if [[ -n "$installed" ]]; then
    while true; do
      age=$(( $(date +%s) - installed ))
      if [[ "$now" == *"/private/var/run/com.apple.security.cryptexd/"* && "$now" != *"/CoreSimulator/Volumes/"* ]]; then
        steady=$((steady + 1))
      else
        steady=0
      fi
      if [[ "$steady" -ge 6 ]] && { [[ "$moved" == true && "$age" -ge 600 ]] || [[ "$age" -ge 900 ]]; }; then
        break
      fi
      if [[ "$age" -ge 1920 ]]; then
        echo "::warning::iOS $IOS_VERSION has not settled 32 min after its download ($now); the tests may lose the simulator."
        break
      fi
      sleep 10
      now=$(runtime_place)
      if [[ "$now" != "$last" ]]; then
        moved=true
        echo "Runtime moved $(( $(date +%s) - installed )) s after its download: $now ($(runtime_mount))"
        last=$now
      fi
    done
    echo "Waited until $(( $(date +%s) - installed )) s after the download."
  fi
  echo "$last" > build/runtime-place.txt
  if [[ "$moved" == true ]]; then
    xcrun simctl shutdown all >/dev/null 2>&1 || true
    killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
    xcrun simctl list runtimes available | grep "iOS $IOS_VERSION" || echo "::warning::iOS $IOS_VERSION is not listed after its move."
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

# Before each test attempt: let the cache build finish, wait for the runtime's moves to be over, then boot the simulator
# and wait for it, so the tests never start on a device a move can kill.
settle_simulator() {
  echo "::group::Settle the simulator"
  echo "iOS $IOS_VERSION ($IOS_BUILD): $(runtime_mount)"
  if [[ -n "${CACHE_PID:-}" ]]; then
    wait "$CACHE_PID" || true
    CACHE_PID=
    cat build/dyld-cache.log
  fi
  wait_for_runtime
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

# xcodebuild's timeouts stop a test that hangs, not a test run that goes silent around it: on PR #271 (run 688) and on
# PR #275 (run 691, 48 min, the simulator settled and 1,537 unit tests passed) the log went quiet after "Test Suite
# 'WeatherRulesTests' started" until the job's limit cancelled it. That line is only where xcodebuild's buffered output
# stopped, so NSUnbufferedIO makes it write each line at once (the log shows where a run stands, and the last lines
# printed on a failure show where it stopped). The tests count as stuck after 12 min with nothing new in the log or the
# result bundle (the first test took 7.5 min to start after the boot on run 691; a hung test fails at 10). Then the
# stacks of the test host and the UI test runner are printed and xcodebuild is stopped, which counts as a lost
# simulator below.
export NSUnbufferedIO=YES
watch_for_silence() {
  local pid
  while sleep 60; do
    [[ -z "$(find build/xcodebuild.log "$RESULT" -mmin -12 -print -quit 2>/dev/null)" ]] || continue
    echo "::warning::No test output for 12 min; stopping xcodebuild."
    touch build/tests-went-silent
    for pid in $(pgrep -f 'TrainTimes.app/TrainTimes|TrainTimesUITests-Runner' || true); do
      echo "::group::Where $(ps -o comm= -p "$pid" 2>/dev/null) ($pid) is stuck"
      sample "$pid" 2 2>&1 | head -n 200 || true
      echo "::endgroup::"
    done
    pkill -INT -f 'xcodebuild test-without-building' || true
    sleep 60
    pkill -KILL -f 'xcodebuild test-without-building' || true
    # Should a child of xcodebuild still hold the pipe, tee would wait for it.
    sleep 30
    pkill -f 'tee build/xcodebuild.log' || true
    return 0
  done
}

# A test that hangs fails after 10 min (xcodebuild's default allowance once timeouts are on) instead of running the job
# into its limit, which cancels the step before anything below can say which test it was. Arguments go to
# xcodebuild (the retry's -skip-testing).
run_tests() {
  local watcher
  rm -rf "$RESULT" build/tests-went-silent
  : > build/xcodebuild.log
  watch_for_silence &
  watcher=$!
  status=0
  xcodebuild test-without-building \
    -project TrainTimes.xcodeproj \
    -scheme TrainTimes \
    -configuration Debug \
    -destination "id=$UDID" \
    -resultBundlePath "$RESULT" \
    -test-timeouts-enabled YES \
    "$@" \
    2>&1 | tee build/xcodebuild.log | "${FORMATTER[@]}" || status=$?
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
}

start_cache_build
build_tests
built=$status
if [[ "$built" -eq 0 ]]; then
  settle_simulator
  run_tests
fi

# On the Xcode 27 image the simulator itself sometimes fails under the tests: its service dies while the test runner is
# installed ("Invalid device state", Mach error -308), or the test host is killed mid-run and the iOS runtime then reads as
# "(null)" ("cannot determine the runtime bundle"). Seen on most TT-243 runs and on main after TT-241 and TT-242, with no
# test at fault. Then restart the simulator service, settle the simulator again (above) and run the tests once more; the
# build is done, so the second run costs the tests only. A real test failure fails the second run too.
SIMULATOR_LOST='Failed to install or launch the test runner|Invalid device state|cannot determine the runtime bundle|Unable to boot device|Unable to find a device matching|crashed with signal term while preparing to run tests'
# No retry once the tests recorded reference snapshots: it would pass against them and leave them uncommitted, while a
# failure here has the workflow commit them and run the tests again itself (with this retry).
recorded=$(git status --porcelain --untracked-files=all -- Tests 2>/dev/null | grep '__Snapshots__' || true)
if [[ "$built" -eq 0 && "$status" -ne 0 && -z "$recorded" ]] && { [[ -e build/tests-went-silent ]] || grep -qE "$SIMULATOR_LOST" build/xcodebuild.log; }; then
  lost=$(grep -oE "$SIMULATOR_LOST" build/xcodebuild.log | head -n 1 || true)
  echo "::warning::The simulator failed under the tests (${lost:-no output for 12 min}); restarting it and running the tests again."
  # The second run leaves out a bundle the first one passed: on PR #271 (run 688) the UI bundle passed in 32 min before
  # the unit bundle lost the simulator, and running both again could not fit in the job's 90 min.
  skip=()
  for bundle in TrainTimesUITests TrainTimesTests; do
    if grep -q "Test Suite '$bundle.xctest' passed" build/xcodebuild.log; then skip+=("-skip-testing:$bundle"); fi
  done
  [[ "${#skip[@]}" -lt 2 ]] || skip=()
  [[ "${#skip[@]}" -eq 0 ]] || echo "Leaving out what passed: ${skip[*]}"
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
  run_tests ${skip[@]+"${skip[@]}"}
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
