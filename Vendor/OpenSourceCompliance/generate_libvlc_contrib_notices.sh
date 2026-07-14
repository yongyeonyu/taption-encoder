#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_PATH="$SCRIPT_DIR/libvlc-ios-contrib-manifest.tsv"
TARBALLS_DIR=""
OUTPUT_PATH=""

usage() {
  echo "Usage: $0 --tarballs-dir DIR --output FILE" >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tarballs-dir)
      [[ $# -ge 2 ]] || usage
      TARBALLS_DIR="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || usage
      OUTPUT_PATH="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -d "$TARBALLS_DIR" ]] || usage
[[ -n "$OUTPUT_PATH" ]] || usage
[[ -f "$MANIFEST_PATH" ]] || {
  echo "Missing manifest: $MANIFEST_PATH" >&2
  exit 1
}

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/taption-libvlc-notices.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
TEMP_OUTPUT="$TEMP_DIR/libVLC-Contrib-Licenses.txt"

cat >"$TEMP_OUTPUT" <<'EOF'
libVLC iOS Static Contrib Notices

The bundled libVLC archive was built with the VideoLAN iOS contrib profile.
The notices below are copied verbatim from the checksum-verified upstream
source archives used by that profile. Pure host build-tool inputs are omitted
from this in-app list but remain preserved in the corresponding-source bundle.

This technical inventory is not a patent clearance or legal approval.
EOF

entry_count=0
runtime_entry_count=0

while IFS=$'\t' read -r archive expected_sha512 role license_files review_status; do
  if [[ "$archive" == "archive" ]]; then
    continue
  fi

  entry_count=$((entry_count + 1))
  archive_path="$TARBALLS_DIR/$archive"
  [[ -f "$archive_path" ]] || {
    echo "Missing contrib source archive: $archive_path" >&2
    exit 1
  }

  actual_sha512="$(shasum -a 512 "$archive_path" | awk '{print $1}')"
  if [[ "$actual_sha512" != "$expected_sha512" ]]; then
    echo "SHA-512 mismatch for $archive" >&2
    echo "expected: $expected_sha512" >&2
    echo "actual:   $actual_sha512" >&2
    exit 1
  fi

  if [[ "$role" == "build-tool-input" ]]; then
    continue
  fi

  runtime_entry_count=$((runtime_entry_count + 1))
  {
    printf '\n\n================================================================\n'
    printf 'Source archive: %s\n' "$archive"
    printf 'Build role: %s\n' "$role"
    printf 'Review status: %s\n' "$review_status"
  } >>"$TEMP_OUTPUT"

  IFS='|' read -r -a license_paths <<<"$license_files"
  for license_path in "${license_paths[@]}"; do
    if ! tar -tf "$archive_path" | grep -Fqx "$license_path"; then
      echo "Missing declared license file $license_path in $archive" >&2
      exit 1
    fi
    {
      printf '\n----------------------------------------------------------------\n'
      printf 'Upstream file: %s\n' "$license_path"
      printf '%s\n' '----------------------------------------------------------------'
      tar -xOf "$archive_path" "$license_path"
    } >>"$TEMP_OUTPUT"
  done
done <"$MANIFEST_PATH"

if [[ "$entry_count" -ne 56 ]]; then
  echo "Expected 56 contrib source archives, found $entry_count" >&2
  exit 1
fi

if [[ "$runtime_entry_count" -ne 54 ]]; then
  echo "Expected 54 runtime or header source entries, found $runtime_entry_count" >&2
  exit 1
fi

# Preserve upstream text while making the generated notice stable for source control.
/usr/bin/perl -pi -e 's/\r$//; s/\t/    /g; s/ +$//' "$TEMP_OUTPUT"

mkdir -p "$(dirname "$OUTPUT_PATH")"
mv "$TEMP_OUTPUT" "$OUTPUT_PATH"
printf 'Verified %d source archives and generated %d in-app entries: %s\n' \
  "$entry_count" "$runtime_entry_count" "$OUTPUT_PATH"
