#!/usr/bin/env bash
# The app ships copies of the design handoff strings and fixtures (TT-101).
# Fails when a copy drifts from design/handoff, so the handoff stays the one source.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
check() {
  if ! cmp -s "$1" "$2"; then
    echo "::error file=$2::$2 differs from $1. Update both in the same PR."
    status=1
  fi
}
check design/handoff/Localizable.strings Resources/en-CA.lproj/Localizable.strings
check design/handoff/Fixtures.json "Preview Content/Fixtures.json"
[[ $status -eq 0 ]] && echo "Handoff copies are in sync."
exit $status
