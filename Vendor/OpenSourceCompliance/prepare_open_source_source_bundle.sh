#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST_PATH="$SCRIPT_DIR/libvlc-ios-contrib-manifest.tsv"
PROVENANCE_PATH="$SCRIPT_DIR/libvlc-ios-provenance.json"

OUTPUT_PATH=""
CONTRIB_TARBALLS_DIR=""
MARKETING_VERSION=""
BUILD_VERSION=""

SWIFTVLC_SOURCE_URL="https://github.com/harflabs/SwiftVLC/archive/9065ad6338ddd2d689bf6220b45e90ab4695b3a8.tar.gz"
SWIFTVLC_SOURCE_SHA256="597406535abac3df68de65ede0ff01b005c9261a316a22302fe96db533a3944b"
VLC_SOURCE_URL="https://code.videolan.org/videolan/vlc/-/archive/c833c4be000b426d73ff4324bec574065f00e3df/vlc-c833c4be000b426d73ff4324bec574065f00e3df.tar.gz"
VLC_SOURCE_SHA256="f4ec8860d690fb3efe393da6c1ddf91d9396a2cc32c3fc0a5bb8a8211b3a4858"
FFMPEG_SOURCE_URL="https://ffmpeg.org/releases/ffmpeg-8.1.1.tar.xz"
FFMPEG_SOURCE_SHA256="b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3"

usage() {
  cat >&2 <<EOF
Usage: $0 \\
  --output FILE.tar.xz \\
  --contrib-tarballs-dir DIR \\
  --marketing-version VERSION \\
  --build-version BUILD
EOF
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || usage
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --contrib-tarballs-dir)
      [[ $# -ge 2 ]] || usage
      CONTRIB_TARBALLS_DIR="$2"
      shift 2
      ;;
    --marketing-version)
      [[ $# -ge 2 ]] || usage
      MARKETING_VERSION="$2"
      shift 2
      ;;
    --build-version)
      [[ $# -ge 2 ]] || usage
      BUILD_VERSION="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$OUTPUT_PATH" ]] || usage
[[ -d "$CONTRIB_TARBALLS_DIR" ]] || usage
[[ -n "$MARKETING_VERSION" ]] || usage
[[ -n "$BUILD_VERSION" ]] || usage

mkdir -p "$(dirname "$OUTPUT_PATH")"
OUTPUT_PATH="$(cd "$(dirname "$OUTPUT_PATH")" && pwd)/$(basename "$OUTPUT_PATH")"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/taption-source-bundle.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
STAGE_DIR="$TEMP_DIR/TaptionEncoder-${MARKETING_VERSION}-${BUILD_VERSION}-CorrespondingSource"
DOWNLOAD_DIR="$TEMP_DIR/downloads"
mkdir -p "$STAGE_DIR/sources/libvlc-contrib" "$STAGE_DIR/taption" "$DOWNLOAD_DIR"

download_and_verify() {
  local url="$1"
  local expected_sha256="$2"
  local destination="$3"

  curl -fL -o "$destination" "$url"
  local actual_sha256
  actual_sha256="$(shasum -a 256 "$destination" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "SHA-256 mismatch for $url" >&2
    echo "expected: $expected_sha256" >&2
    echo "actual:   $actual_sha256" >&2
    exit 1
  fi
}

download_and_verify \
  "$SWIFTVLC_SOURCE_URL" \
  "$SWIFTVLC_SOURCE_SHA256" \
  "$STAGE_DIR/sources/SwiftVLC-0.10.0.tar.gz"
download_and_verify \
  "$VLC_SOURCE_URL" \
  "$VLC_SOURCE_SHA256" \
  "$STAGE_DIR/sources/vlc-c833c4be000b426d73ff4324bec574065f00e3df.tar.gz"
download_and_verify \
  "$FFMPEG_SOURCE_URL" \
  "$FFMPEG_SOURCE_SHA256" \
  "$STAGE_DIR/sources/ffmpeg-8.1.1.tar.xz"

archive_count=0
while IFS=$'\t' read -r archive expected_sha512 role license_files review_status; do
  if [[ "$archive" == "archive" ]]; then
    continue
  fi
  archive_count=$((archive_count + 1))
  source_path="$CONTRIB_TARBALLS_DIR/$archive"
  [[ -f "$source_path" ]] || {
    echo "Missing contrib source archive: $source_path" >&2
    exit 1
  }
  actual_sha512="$(shasum -a 512 "$source_path" | awk '{print $1}')"
  if [[ "$actual_sha512" != "$expected_sha512" ]]; then
    echo "SHA-512 mismatch for $archive" >&2
    exit 1
  fi
  cp "$source_path" "$STAGE_DIR/sources/libvlc-contrib/$archive"
done <"$MANIFEST_PATH"

if [[ "$archive_count" -ne 56 ]]; then
  echo "Expected 56 libVLC contrib source archives, found $archive_count" >&2
  exit 1
fi

cp "$MANIFEST_PATH" "$STAGE_DIR/"
cp "$PROVENANCE_PATH" "$STAGE_DIR/"
cp "$SCRIPT_DIR/README.md" "$STAGE_DIR/OPEN_SOURCE_DISTRIBUTION_README.md"
cp "$SCRIPT_DIR/LEGAL_REVIEW_PACKET.md" "$STAGE_DIR/"
cp "$SCRIPT_DIR/legal-approval.pending.json" "$STAGE_DIR/"
cp "$SCRIPT_DIR/generate_libvlc_contrib_notices.sh" "$STAGE_DIR/"
cp "$SCRIPT_DIR/prepare_open_source_source_bundle.sh" "$STAGE_DIR/"
cp "$SCRIPT_DIR/prepare_relink_materials.sh" "$STAGE_DIR/"
cp "$SCRIPT_DIR/verify_public_distribution_gate.sh" "$STAGE_DIR/"
cp "$ROOT_DIR/TaptionEncoder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
  "$STAGE_DIR/Package.resolved"
cp -R "$ROOT_DIR/Vendor/FFmpegLGPLDecodeBridge/Sources" \
  "$STAGE_DIR/taption/FFmpegLGPLDecodeBridge-Sources"
cp "$ROOT_DIR/Vendor/FFmpegLGPLDecodeBridge/build_ffmpeg_lgpl_decode_bridge.sh" \
  "$STAGE_DIR/taption/"
cp "$ROOT_DIR/Vendor/FFmpegLGPLDecodeBridge/FFMPEG_LGPL_DECODE_BRIDGE_BUILD.txt" \
  "$STAGE_DIR/taption/"
cp -R "$ROOT_DIR/TaptionEncoder/OpenSourceNotices" "$STAGE_DIR/taption/"

"$SCRIPT_DIR/generate_libvlc_contrib_notices.sh" \
  --tarballs-dir "$CONTRIB_TARBALLS_DIR" \
  --output "$STAGE_DIR/taption/libVLC-Contrib-Licenses.generated.txt"

cat >"$STAGE_DIR/release-metadata.json" <<EOF
{
  "bundleIdentifier": "com.taption.encoder",
  "marketingVersion": "$MARKETING_VERSION",
  "buildVersion": "$BUILD_VERSION",
  "sourceInventoryDate": "2026-07-14"
}
EOF

cat >"$STAGE_DIR/SOURCE_BUNDLE_CONTENTS.txt" <<'EOF'
This bundle contains the pinned SwiftVLC and VideoLAN VLC sources, the complete
checksum-verified VideoLAN iOS contrib source set, FFmpeg 8.1.1 source, Taption
Encoder's FFmpeg bridge source and build recipe, and shipped notice resources.

It does not contain the proprietary application object files required for an
LGPL static relink. Those release-specific materials are a separate gate.
EOF

(
  cd "$STAGE_DIR"
  find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | while read -r path; do
    shasum -a 256 "$path"
  done >SHA256SUMS
)

find "$STAGE_DIR" -exec touch -h -t 202607140000 {} +
rm -f "$OUTPUT_PATH"
(
  cd "$TEMP_DIR"
  COPYFILE_DISABLE=1 tar -cJf "$OUTPUT_PATH" "$(basename "$STAGE_DIR")"
)

shasum -a 256 "$OUTPUT_PATH"
