#!/bin/bash
# Restores the real-world sample library that commit 02e3ad4 removed, and turns
# the retired proof suites back on.
#
# Why restore instead of generate: those 57 samples are real encoder output —
# Cinepak from a 1990s QuickTime file, Sorenson Video 1, RealVideo, RoQ, ASUS V1 —
# and the tests that use them exist to prove the app can *read* formats it did not
# write. A fixture produced by this machine's FFmpeg proves nothing about that, and
# the suite says so explicitly: testBundledSampleSourceNoticeRejectsGeneratedOnlyFixtures
# fails if the source notice mentions FFmpeg-generated material.
#
# The files are still in git history, so nothing has to be regenerated. They are
# restored into a git-ignored folder, used, and can be removed again:
#
#   ./scripts/restore-retired-samples.sh          # restore + enable the proofs
#   ./scripts/restore-retired-samples.sh --clean  # remove both
#
# After restoring, the opt-in suites run through the normal gate:
#
#   ./scripts/verify.sh
#
# They are excluded from the default suite by name (retiredSourceOnlyProofTestNames)
# unless the flag file exists, so a restore changes nothing until you ask for it.

set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="TaptionEncoder/TestVideos"
SEEDER="TaptionEncoder/App/TestVideoSeeder.swift"
NOTICE="SAMPLE_SOURCES.txt"
FLAG="/tmp/taption_run_retired_proof_tests"

if [ "${1:-}" = "--clean" ]; then
  rm -rf "$TARGET"
  rm -f "$FLAG"
  echo "==> Removed $TARGET and $FLAG"
  echo "==> The default suite is unchanged; the retired proofs are off again."
  exit 0
fi

if [ ! -f "$SEEDER" ]; then
  echo "error: $SEEDER not found; run this from a checkout of the repository" >&2
  exit 1
fi

# The expected list is read out of the Swift source rather than copied here. If the
# catalog changes shape, this script has to notice instead of restoring a stale set.
expected=$(sed -n '/expectedBundledVideoSampleFilenames = \[/,/^    \]/p' "$SEEDER" \
  | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
expected_count=$(printf '%s\n' "$expected" | wc -l | tr -d ' ')
if [ "$expected_count" -lt 10 ]; then
  echo "error: parsed only $expected_count filenames out of $SEEDER." >&2
  echo "       The array is probably no longer a plain list of string literals." >&2
  exit 1
fi
echo "==> $expected_count samples expected by TaptionTestVideoSeeder"

# The folder was deleted, not rewritten, so the commit that removed it still points
# at its content. Locating it by that commit keeps this working if hashes move.
removal=$(git log --diff-filter=D --format=%H -1 -- "$TARGET")
if [ -z "$removal" ]; then
  echo "error: no commit in this clone ever deleted $TARGET." >&2
  exit 1
fi
source_ref="$removal^"
echo "==> Restoring from $(git log -1 --format='%h %s' "$source_ref")"

rm -rf "$TARGET"
mkdir -p "$TARGET"
git archive "$source_ref" "$TARGET" | tar -x -C .

# History holds three samples that are no longer in the expected catalog
# (H.264 AC3 / H.264 EAC3 / Theora Vorbis). Keeping them would fail the set-equality
# assertion in testBundledTestVideosMatchCurrentLaunchVideoSupport, so they go.
pruned=0
while IFS= read -r file; do
  name=$(basename "$file")
  if [ "$name" = "$NOTICE" ]; then
    continue
  fi
  if ! printf '%s\n' "$expected" | grep -qxF "$name"; then
    rm -f "$file"
    echo "    pruned (no longer expected): $name"
    pruned=$((pruned + 1))
  fi
done < <(find "$TARGET" -type f)

present=$(find "$TARGET" -type f ! -name "$NOTICE" | wc -l | tr -d ' ')
if [ "$present" != "$expected_count" ]; then
  echo "error: $present samples present, $expected_count expected." >&2
  exit 1
fi

if [ ! -f "$TARGET/$NOTICE" ]; then
  echo "error: $NOTICE is missing; the source-notice test will fail." >&2
  exit 1
fi

touch "$FLAG"

echo "==> Restored $present samples ($(du -sh "$TARGET" | cut -f1)), pruned $pruned"
echo "==> Enabled: $FLAG"
echo
echo "    ./scripts/verify.sh            # default suite plus the retired proofs"
echo "    ./scripts/restore-retired-samples.sh --clean"
