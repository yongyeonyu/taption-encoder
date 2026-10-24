#!/bin/bash
# Build and test the app the way CI would, using the local Xcode.
#
# Why this exists: GitHub's macos-26 runner image ships Xcode 26.6 only, and this
# project needs the iOS 27 SDK, so the hosted CI build is skipped (see
# docs/code-review/README.md §6). Until that changes, this script *is* the gate.
#
# Usage:
#   ./scripts/verify.sh            # build + full test suite
#   ./scripts/verify.sh --build    # build only, much faster
#
# Exit code is 0 only when everything passed.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="TaptionEncoder.xcodeproj"
SCHEME="TaptionEncoder"
DERIVED="${TAPTION_DERIVED_DATA:-/tmp/taption-verify}"
BUILD_ONLY=0

if [ "${1:-}" = "--build" ]; then
  BUILD_ONLY=1
fi

echo "==> Xcode: $(xcodebuild -version | head -1)"

if [ -n "${TAPTION_TEST_DESTINATION:-}" ]; then
  DESTINATION="$TAPTION_TEST_DESTINATION"
else
  UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1 || true)
  if [ -z "$UDID" ]; then
    echo "==> No booted simulator, creating one"
    RUNTIME=$(xcrun simctl list runtimes | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | tail -1)
    TYPE=""
    for name in "iPhone 18 Pro" "iPhone 17" "iPhone 16"; do
      line=$(xcrun simctl list devicetypes | grep -F "$name (" | head -1 || true)
      if [ -n "$line" ]; then
        TYPE=$(echo "$line" | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9.-]+')
        break
      fi
    done
    if [ -z "$RUNTIME" ] || [ -z "$TYPE" ]; then
      echo "error: no iOS runtime or iPhone device type available" >&2
      exit 1
    fi
    UDID=$(xcrun simctl create "verify-phone" "$TYPE" "$RUNTIME")
    xcrun simctl boot "$UDID"
  fi
  DESTINATION="id=$UDID"
fi

echo "==> Destination: $DESTINATION"

COMMON=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED"
  # swift-plugin-server is blocked by sandbox-exec here, which breaks the
  # Observation macro expansion. Required on this machine.
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'
)

if [ "$BUILD_ONLY" = "1" ]; then
  echo "==> Building"
  xcodebuild build "${COMMON[@]}"
  echo "==> Build passed"
  exit 0
fi

echo "==> Building and testing (this takes a few minutes)"
# Output goes to a file, never through a pipe: a long-lived pipe lets a lingering
# simulator child hold the write end open, and the reader waits for an EOF that
# never comes. That is what made the pre-push hook look like it hung after the
# tests had already passed.
LOG=${TAPTION_LOG:-/tmp/taption-verify.log}
: > "$LOG"

# Keeping the result bundle means a failure can be opened in Xcode instead of
# being reconstructed from grep. CI overrides the path so it can upload it.
RESULT_BUNDLE=${TAPTION_RESULT_BUNDLE:-/tmp/taption-verify.xcresult}
rm -rf "$RESULT_BUNDLE"

# -parallel-testing-enabled NO: parallel clones occasionally stall this suite.
xcodebuild test "${COMMON[@]}" -resultBundlePath "$RESULT_BUNDLE" \
  -parallel-testing-enabled NO > "$LOG" 2>&1 &
XCB_PID=$!

# Bounded wait. The loop runs in this shell on purpose: a `( sleep N; kill ) &`
# watchdog leaves an orphan sleep holding our stdout, which hangs the caller
# instead of protecting it.
#
# The grace period is not paranoia. xcodebuild on this machine routinely stops
# emitting output and never exits, stuck on a simctl child that has already done
# its job. Two different hangs have been observed, so the terminal signal is
# whichever of these lands first:
#
#   Test Suite 'All tests' passed   <- xctest, printed at the end of the session
#   ** TEST SUCCEEDED **            <- xcodebuild, printed after that ... or not
#
# The second one is NOT reliable: one run finished the whole suite, printed the
# summary, and then hung before ever writing "** TEST SUCCEEDED **". Treating
# that line as the only proof of success turns a passing run into a red build
# after the full timeout. So either line ends the wait, and the verdict is read
# from the log rather than from the exit status.
LIMIT=1800
GRACE=45
WAITED=0
DONE_AT=""
while kill -0 "$XCB_PID" 2>/dev/null; do
  if [ -z "$DONE_AT" ] && grep -qE "\*\* (TEST|BUILD) (SUCCEEDED|FAILED) \*\*|Test Suite 'All tests' (passed|failed)" "$LOG"; then
    DONE_AT=$WAITED
  fi
  if [ -n "$DONE_AT" ] && [ $((WAITED - DONE_AT)) -ge "$GRACE" ]; then
    echo "==> Result is in the log but xcodebuild is still running, stopping it" >&2
    kill -TERM "$XCB_PID" 2>/dev/null || true
    sleep 2
    kill -9 "$XCB_PID" 2>/dev/null || true
    break
  fi
  if [ "$WAITED" -ge "$LIMIT" ]; then
    echo "==> Timed out after ${LIMIT}s, killing xcodebuild" >&2
    kill -9 "$XCB_PID" 2>/dev/null || true
    break
  fi
  sleep 5
  WAITED=$((WAITED + 5))
done

set +e
wait "$XCB_PID" 2>/dev/null
STATUS=$?
set -e

grep -E "error:|Test Case .* failed|Executed [0-9]+ tests, with|TEST (SUCCEEDED|FAILED)" "$LOG" | tail -20 || true

if grep -qE "\*\* (TEST|BUILD) FAILED \*\*|Test Suite 'All tests' failed|Test Case .* failed" "$LOG"; then
  echo "==> FAILED. Full log: $LOG" >&2
  exit 1
fi

# Deliberately ignores $STATUS: when we stopped a hung xcodebuild above, its exit
# code is our own SIGTERM, not a verdict. The log is the source of truth.
if ! grep -qE "\*\* TEST SUCCEEDED \*\*|Test Suite 'All tests' passed" "$LOG"; then
  echo "==> Could not determine the result (xcodebuild exited $STATUS). Full log: $LOG" >&2
  exit 1
fi

echo "==> All tests passed"
