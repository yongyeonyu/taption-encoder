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
# Environment:
#   TAPTION_SIMULATOR_NAME         which dedicated simulator this run owns
#                                  (default: verify-ci under CI, else verify-local)
#   TAPTION_TEST_DESTINATION       use this destination verbatim, skip device setup
#   TAPTION_DERIVED_DATA           derived data path
#   TAPTION_LOG / TAPTION_RESULT_BUNDLE   where the log and result bundle go
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
  # ---------------------------------------------------------------------------
  # Simulator isolation
  #
  # This Mac is the CI runner *and* the development machine. The runner executes
  # jobs out of its own work folder, but both sides end up in this script, and
  # the selection used to be "whatever is booted, first match":
  #
  #   UDID=$(xcrun simctl list devices booted | grep -oE '<uuid>' | head -1)
  #
  # So two runs landed on the same device, and the second `xcodebuild test`
  # SIGKILLed the first one's test host. That is exactly what a red CI looked
  # like while the same suite passed locally: 473 passed, 3 "Test crashed with
  # signal kill" (all on the heaviest VC-1 encodes), plus "Failure collecting
  # diagnostics from simulator: Timed out after 600.0 seconds". Nothing was
  # wrong with the code, and re-running with no local run in flight turned it
  # green — which is the tell that the two runs were fighting over one device.
  #
  # There is no shared state to arbitrate here, so the fix is to stop sharing:
  # each owner gets its own device, named after itself, and never looks at what
  # else happens to be booted. CI and a local run can then overlap safely.
  # ---------------------------------------------------------------------------
  if [ -n "${TAPTION_SIMULATOR_NAME:-}" ]; then
    SIM_NAME="$TAPTION_SIMULATOR_NAME"
  elif [ "${CI:-}" = "true" ]; then
    SIM_NAME="verify-ci"
  else
    SIM_NAME="verify-local"
  fi

  # The lock names its owner, so a run that died without cleaning up — SIGKILL, or
  # bash aborting on a script that was edited while it ran — can be told apart from
  # a live one. Without that, a dead lock blocks this owner until someone notices.
  tmp_root="${TMPDIR:-/tmp}"
  tmp_root="${tmp_root%/}"
  LOCK="$tmp_root/taption-verify-${SIM_NAME}.lock"

  if ! mkdir "$LOCK" 2>/dev/null; then
    holder=$(cat "$LOCK/pid" 2>/dev/null || true)
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
      echo "error: the '$SIM_NAME' simulator is in use by pid $holder (lock: $LOCK)." >&2
      echo "       Two runs on one device kill each other's test host, so this one stops." >&2
      echo "       Wait for that run, or claim another device:" >&2
      echo "         TAPTION_SIMULATOR_NAME=verify-2 ./scripts/verify.sh" >&2
      exit 1
    fi
    echo "==> Reclaiming the '$SIM_NAME' lock from a run that is gone (pid ${holder:-unknown})"
    rm -rf "$LOCK"
    if ! mkdir "$LOCK" 2>/dev/null; then
      echo "error: could not claim the '$SIM_NAME' simulator lock: $LOCK" >&2
      exit 1
    fi
  fi
  echo $$ > "$LOCK/pid"
  trap 'rm -rf "$LOCK" 2>/dev/null || true' EXIT INT TERM

  # Matched on " name (" so a device called verify-local2 cannot be mistaken for
  # verify-local. The name is the whole contract, so this has to be exact.
  UDID=$(xcrun simctl list devices 2>/dev/null \
    | grep -F " $SIM_NAME (" \
    | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' \
    | head -1 || true)

  if [ -n "$UDID" ]; then
    echo "==> Using simulator $SIM_NAME ($UDID)"
  else
    echo "==> Creating simulator $SIM_NAME"
    # A runtime does not support every device type. The iOS 27.1 runtime only ships
    # for the Duo-era models, so pairing it with an iPhone 18 Pro is refused with
    # "Incompatible device" — and `simctl create` reports that on stdout while still
    # exiting 0, so the reply has to be validated rather than trusted. Try the newest
    # runtime first, then older ones.
    for runtime in $(xcrun simctl list runtimes \
      | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | sort -rV || true); do
      for name in "iPhone 18 Pro" "iPhone 17" "iPhone 16"; do
        line=$(xcrun simctl list devicetypes | grep -F "$name (" | head -1 || true)
        if [ -z "$line" ]; then
          continue
        fi
        TYPE=$(echo "$line" | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9.-]+')
        created=$(xcrun simctl create "$SIM_NAME" "$TYPE" "$runtime" 2>&1 || true)
        if echo "$created" | grep -qE '^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$'; then
          UDID="$created"
          echo "==> Created $SIM_NAME on $runtime"
          break 2
        fi
      done
    done
    if [ -z "$UDID" ]; then
      echo "error: could not create a '$SIM_NAME' simulator on any installed runtime." >&2
      echo "       Create one by hand and name it '$SIM_NAME', or point" >&2
      echo "       TAPTION_SIMULATOR_NAME at an existing device." >&2
      exit 1
    fi
  fi

  # Erased on every run. A device kept across runs also keeps the previous run's
  # app container, and the leftover UserDefaults makes a handful of tests fail
  # only in a full-suite run — testAutoSizeShowsEstimatedOutputInMainTileAndPopoverValue
  # is the usual one, and it passes when run alone. That is a confusing failure
  # to debug, and erasing costs seconds, so it is not optional.
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  xcrun simctl erase "$UDID" 2>/dev/null || true
  # Wait for the boot to finish. Without this the first test can be launched into
  # a half-booted device and fail with "Invalid device state" / "(ipc/mig) server died".
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

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
