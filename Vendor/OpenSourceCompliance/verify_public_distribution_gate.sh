#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_PATH=""
DIST_IPA_PATH=""
SOURCE_BUNDLE_PATH=""
RELINK_BUNDLE_PATH=""
LEGAL_APPROVAL_PATH=""
LEGAL_APPROVAL_REQUIRED=false
APP_SIZE_REPORT_PATH=""

usage() {
  cat >&2 <<EOF
Usage: $0 \\
  --archive TaptionEncoder.xcarchive \\
  --distribution-ipa "Taption Encoder.ipa" \\
  --source-bundle CorrespondingSource.tar.xz \\
  --relink-bundle RelinkMaterials.tar.xz \\
  --app-size-report "App Thinning Size Report.txt" \\
  [--legal-approval approval.json] [--require-legal-approval]

The default gate checks technical release materials, not legal approval.
Supplying --legal-approval enables strict, version/digest-bound approval checks.
--require-legal-approval blocks when no approval record is supplied.
EOF
  exit "${1:-64}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      [[ $# -ge 2 ]] || usage
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --distribution-ipa)
      [[ $# -ge 2 ]] || usage
      DIST_IPA_PATH="$2"
      shift 2
      ;;
    --source-bundle)
      [[ $# -ge 2 ]] || usage
      SOURCE_BUNDLE_PATH="$2"
      shift 2
      ;;
    --relink-bundle)
      [[ $# -ge 2 ]] || usage
      RELINK_BUNDLE_PATH="$2"
      shift 2
      ;;
    --legal-approval)
      [[ $# -ge 2 ]] || usage
      LEGAL_APPROVAL_PATH="$2"
      LEGAL_APPROVAL_REQUIRED=true
      shift 2
      ;;
    --require-legal-approval)
      LEGAL_APPROVAL_REQUIRED=true
      shift
      ;;
    --app-size-report)
      [[ $# -ge 2 ]] || usage
      APP_SIZE_REPORT_PATH="$2"
      shift 2
      ;;
    --help|-h)
      usage 0
      ;;
    *)
      usage
      ;;
  esac
done

fail() {
  echo "PUBLIC_DISTRIBUTION_GATE=BLOCKED" >&2
  echo "$1" >&2
  exit 1
}

[[ -d "$ARCHIVE_PATH" ]] || fail "Missing release xcarchive: $ARCHIVE_PATH"
[[ -f "$DIST_IPA_PATH" ]] || fail "Missing App Store distribution IPA: $DIST_IPA_PATH"
[[ -f "$SOURCE_BUNDLE_PATH" ]] || fail "Missing corresponding-source bundle: $SOURCE_BUNDLE_PATH"
[[ -f "$RELINK_BUNDLE_PATH" ]] || fail "Missing relinking bundle: $RELINK_BUNDLE_PATH"
[[ -f "$APP_SIZE_REPORT_PATH" ]] || fail "Missing App Thinning Size Report: $APP_SIZE_REPORT_PATH"
if [[ "$LEGAL_APPROVAL_REQUIRED" == true ]]; then
  [[ -f "$LEGAL_APPROVAL_PATH" ]] || fail "Missing external legal approval record: $LEGAL_APPROVAL_PATH"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/taption-public-gate.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

APPLICATIONS_DIR="$ARCHIVE_PATH/Products/Applications"
[[ -d "$APPLICATIONS_DIR" ]] || fail "The xcarchive has no Products/Applications directory."
APP_DIR="$(find "$APPLICATIONS_DIR" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$APP_DIR" ]] || fail "The xcarchive does not contain an application bundle."
INFO_PLIST="$APP_DIR/Info.plist"
[[ -f "$INFO_PLIST" ]] || fail "Missing application Info.plist in xcarchive."
ARCHIVE_INFO_PLIST="$ARCHIVE_PATH/Info.plist"
[[ -f "$ARCHIVE_INFO_PLIST" ]] || fail "Missing xcarchive Info.plist."

plist_value() {
  /usr/libexec/PlistBuddy -c "Print:$2" "$1" 2>/dev/null || true
}

json_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null || true
}

BUNDLE_ID="$(plist_value "$INFO_PLIST" CFBundleIdentifier)"
MARKETING_VERSION="$(plist_value "$INFO_PLIST" CFBundleShortVersionString)"
BUILD_VERSION="$(plist_value "$INFO_PLIST" CFBundleVersion)"
PLATFORM_NAME="$(plist_value "$INFO_PLIST" DTPlatformName)"
ARCHIVE_APP_PATH="$(plist_value "$ARCHIVE_INFO_PLIST" ApplicationProperties:ApplicationPath)"
APP_EXECUTABLE_NAME="$(plist_value "$INFO_PLIST" CFBundleExecutable)"
APP_EXECUTABLE="$APP_DIR/$APP_EXECUTABLE_NAME"

[[ "$BUNDLE_ID" == "com.taption.encoder" ]] || fail "Unexpected bundle identifier: $BUNDLE_ID"
[[ -n "$MARKETING_VERSION" ]] || fail "Missing marketing version in xcarchive."
[[ -n "$BUILD_VERSION" ]] || fail "Missing build version in xcarchive."
[[ -f "$APP_EXECUTABLE" ]] || fail "Missing release app executable."
[[ "$PLATFORM_NAME" == "iphoneos" ]] || fail "Archive is not an iOS device build: $PLATFORM_NAME"
[[ "$ARCHIVE_APP_PATH" == "Applications/$(basename "$APP_DIR")" ]] || \
  fail "xcarchive application path does not match the bundled app."
codesign --verify --deep --strict "$APP_DIR" || fail "Release app code signature verification failed."

ARCHIVE_DSYM="$(find "$ARCHIVE_PATH/dSYMs" -maxdepth 1 -type d -name "$APP_EXECUTABLE_NAME.app.dSYM" -print -quit 2>/dev/null || true)"
[[ -n "$ARCHIVE_DSYM" ]] || fail "Release archive is missing the app dSYM."
DSYM_EXECUTABLE="$ARCHIVE_DSYM/Contents/Resources/DWARF/$APP_EXECUTABLE_NAME"
[[ -f "$DSYM_EXECUTABLE" ]] || fail "Release archive app dSYM has no DWARF executable."
APP_UUIDS="$(xcrun dwarfdump --uuid "$APP_EXECUTABLE" | awk '{print $2}' | LC_ALL=C sort)"
DSYM_UUIDS="$(xcrun dwarfdump --uuid "$DSYM_EXECUTABLE" | awk '{print $2}' | LC_ALL=C sort)"
[[ -n "$APP_UUIDS" && "$APP_UUIDS" == "$DSYM_UUIDS" ]] || \
  fail "Release app and dSYM UUIDs do not match."

verify_no_local_build_paths() {
  local bundle_path="$1"
  local bundle_label="$2"
  local candidate

  while IFS= read -r -d '' candidate; do
    if ! file "$candidate" | grep -q 'Mach-O'; then
      continue
    fi
    if strings -a "$candidate" | grep -Eq '/Users/[^/]+/|/private/tmp/|/var/folders/'; then
      fail "$bundle_label exposes a local build/source path: ${candidate#"$bundle_path"/}"
    fi
  done < <(find "$bundle_path" -type f -print0)
}

verify_no_local_build_paths "$APP_DIR" "Release app bundle"
if find "$APP_DIR" -type f \( \
  -name '*.o' -o \
  -name '*.a' -o \
  -name '*.d' -o \
  -name '*.dia' -o \
  -name '*.swiftdeps' -o \
  -name '*.swiftsourceinfo' -o \
  -name '*.swiftinterface' \
\) -print -quit | grep -q .; then
  fail "Release app bundle contains compiler, object, archive, or interface artifacts."
fi

unzip -tq "$DIST_IPA_PATH" >/dev/null || fail "App Store distribution IPA is not a valid ZIP archive."
mkdir -p "$TEMP_DIR/distribution-ipa"
unzip -q "$DIST_IPA_PATH" -d "$TEMP_DIR/distribution-ipa" || \
  fail "Could not extract App Store distribution IPA."
DIST_APP_DIR="$(find "$TEMP_DIR/distribution-ipa/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$DIST_APP_DIR" ]] || fail "Distribution IPA does not contain a Payload application."
DIST_INFO_PLIST="$DIST_APP_DIR/Info.plist"
[[ -f "$DIST_INFO_PLIST" ]] || fail "Distribution IPA application has no Info.plist."
[[ "$(plist_value "$DIST_INFO_PLIST" CFBundleIdentifier)" == "$BUNDLE_ID" ]] || \
  fail "Distribution IPA bundle identifier does not match the xcarchive."
[[ "$(plist_value "$DIST_INFO_PLIST" CFBundleShortVersionString)" == "$MARKETING_VERSION" ]] || \
  fail "Distribution IPA marketing version does not match the xcarchive."
[[ "$(plist_value "$DIST_INFO_PLIST" CFBundleVersion)" == "$BUILD_VERSION" ]] || \
  fail "Distribution IPA build version does not match the xcarchive."
if find "$TEMP_DIR/distribution-ipa" -type d -name '*.dSYM' -print -quit | grep -q .; then
  fail "Distribution IPA unexpectedly contains a dSYM bundle."
fi
if find "$DIST_APP_DIR" -type f \( \
  -name '*.o' -o \
  -name '*.a' -o \
  -name '*.d' -o \
  -name '*.dia' -o \
  -name '*.swiftdeps' -o \
  -name '*.swiftsourceinfo' -o \
  -name '*.swiftinterface' \
\) -print -quit | grep -q .; then
  fail "Distribution IPA contains compiler, object, archive, or interface artifacts."
fi
verify_no_local_build_paths "$DIST_APP_DIR" "Distribution IPA app bundle"
codesign --verify --deep --strict "$DIST_APP_DIR" || fail "Distribution IPA code signature verification failed."
DIST_SIGNATURE="$(codesign -d --verbose=4 "$DIST_APP_DIR" 2>&1 || true)"
grep -Eq '^Authority=.*Apple Distribution' <<<"$DIST_SIGNATURE" || \
  fail "Distribution IPA is not signed with an Apple Distribution identity."
codesign -d --entitlements :- "$DIST_APP_DIR" >"$TEMP_DIR/distribution-entitlements.plist" 2>/dev/null || \
  fail "Could not read distribution IPA entitlements."
/usr/bin/plutil -lint "$TEMP_DIR/distribution-entitlements.plist" >/dev/null || \
  fail "Distribution IPA entitlements are invalid."
[[ "$(plist_value "$TEMP_DIR/distribution-entitlements.plist" get-task-allow)" == "false" ]] || \
  fail "Distribution IPA unexpectedly permits debugger attachment."

for notice_name in \
  LGPL-2.1.txt \
  SwiftVLC-MIT.txt \
  libVLC-LGPL-Notice.txt \
  libVLC-Contrib-Licenses.txt \
  FFmpeg-LGPL-Decode-Bridge.txt; do
  notice_path="$APP_DIR/OpenSourceNotices/$notice_name"
  [[ -s "$notice_path" ]] || fail "Release app is missing open-source notice: $notice_name"
  distribution_notice_path="$DIST_APP_DIR/OpenSourceNotices/$notice_name"
  [[ -s "$distribution_notice_path" ]] || \
    fail "Distribution IPA is missing open-source notice: $notice_name"
done

APP_BYTES="$(find "$APP_DIR" -type f -exec stat -f '%z' {} + | awk '{ total += $1 } END { printf "%.0f", total }')"
MAX_APP_BYTES=$((4 * 1024 * 1024 * 1024))
[[ "$APP_BYTES" -le "$MAX_APP_BYTES" ]] || fail "Uncompressed app bundle exceeds Apple's 4 GB limit."

MACHO_REPORT="$TEMP_DIR/macho-text-sizes.tsv"
: >"$MACHO_REPORT"
while IFS= read -r -d '' candidate; do
  if ! file "$candidate" | grep -q 'Mach-O.*executable'; then
    continue
  fi
  text_bytes="$(xcrun size -m "$candidate" | awk '/^Segment __TEXT:/ { total += $3 } END { printf "%.0f", total }')"
  [[ -n "$text_bytes" ]] || fail "Could not measure Mach-O __TEXT size: $candidate"
  printf '%s\t%s\n' "$text_bytes" "${candidate#"$APP_DIR"/}" >>"$MACHO_REPORT"
  if [[ "$text_bytes" -gt $((500 * 1024 * 1024)) ]]; then
    fail "Mach-O __TEXT size exceeds Apple's 500 MB limit: $candidate"
  fi
done < <(find "$APP_DIR" -type f -print0)
[[ -s "$MACHO_REPORT" ]] || fail "No Mach-O executable was found in the release app."

grep -Fq "App Thinning Size Report" "$APP_SIZE_REPORT_PATH" || \
  fail "The supplied file is not an App Thinning Size Report."
if grep -Eiq 'exceeds|too large' "$APP_SIZE_REPORT_PATH"; then
  fail "The App Thinning Size Report contains a size-limit warning."
fi

mkdir -p "$TEMP_DIR/source" "$TEMP_DIR/relink"
tar -xJf "$SOURCE_BUNDLE_PATH" -C "$TEMP_DIR/source" || fail "Could not extract source bundle."
SOURCE_ROOT="$(find "$TEMP_DIR/source" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -n "$SOURCE_ROOT" ]] || fail "Source bundle has no top-level directory."
[[ -f "$SOURCE_ROOT/SHA256SUMS" ]] || fail "Source bundle has no SHA256SUMS."
(
  cd "$SOURCE_ROOT"
  shasum -a 256 -c SHA256SUMS >/dev/null
) || fail "Source bundle internal checksum verification failed."
SOURCE_METADATA_PATH="$SOURCE_ROOT/release-metadata.json"
[[ -f "$SOURCE_METADATA_PATH" ]] || fail "Source bundle has no release-metadata.json."
/usr/bin/plutil -convert xml1 -o /dev/null "$SOURCE_METADATA_PATH" || \
  fail "Invalid source release metadata JSON."

[[ "$(json_value "$SOURCE_METADATA_PATH" bundleIdentifier)" == "$BUNDLE_ID" ]] || \
  fail "Source bundle identifier does not match the xcarchive."
[[ "$(json_value "$SOURCE_METADATA_PATH" marketingVersion)" == "$MARKETING_VERSION" ]] || \
  fail "Source bundle marketing version does not match the xcarchive."
[[ "$(json_value "$SOURCE_METADATA_PATH" buildVersion)" == "$BUILD_VERSION" ]] || \
  fail "Source bundle build version does not match the xcarchive."

tar -xJf "$RELINK_BUNDLE_PATH" -C "$TEMP_DIR/relink" || fail "Could not extract relinking bundle."
RELINK_ROOT="$(find "$TEMP_DIR/relink" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -n "$RELINK_ROOT" ]] || fail "Relinking bundle has no top-level directory."
for required_member in \
  RELINK_README.txt \
  LINK_COMMAND.txt \
  SYSTEM_LINK_INPUTS.txt \
  Package.resolved \
  relink-metadata.json \
  SHA256SUMS \
  TaptionEncoder-AppObjects.tar.xz; do
  if [[ ! -f "$RELINK_ROOT/$required_member" ]]; then
    fail "Relinking bundle is missing $required_member."
  fi
done

(
  cd "$RELINK_ROOT"
  shasum -a 256 -c SHA256SUMS >/dev/null
) || fail "Relinking bundle internal checksum verification failed."
RELINK_METADATA_PATH="$RELINK_ROOT/relink-metadata.json"
/usr/bin/plutil -convert xml1 -o /dev/null "$RELINK_METADATA_PATH" || \
  fail "Invalid relinking release metadata JSON."
case "$(json_value "$RELINK_METADATA_PATH" technicalStatus)" in
  technical-relink-materials|candidate-external-legal-review-required)
    # Accept preserved older packets without turning their warning into a gate.
    ;;
  *)
    fail "Relinking metadata has an unknown technical status."
    ;;
esac
[[ "$(json_value "$RELINK_METADATA_PATH" bundleIdentifier)" == "$BUNDLE_ID" ]] || \
  fail "Relinking bundle identifier does not match the xcarchive."
[[ "$(json_value "$RELINK_METADATA_PATH" marketingVersion)" == "$MARKETING_VERSION" ]] || \
  fail "Relinking bundle marketing version does not match the xcarchive."
[[ "$(json_value "$RELINK_METADATA_PATH" buildVersion)" == "$BUILD_VERSION" ]] || \
  fail "Relinking bundle build version does not match the xcarchive."
RELINK_OBJECT_COUNT="$(json_value "$RELINK_METADATA_PATH" objectCount)"
[[ "$RELINK_OBJECT_COUNT" =~ ^[1-9][0-9]*$ ]] || fail "Relinking object count is invalid."
grep -Fq -- '-lvlc' "$RELINK_ROOT/LINK_COMMAND.txt" || \
  fail "Relinking command does not include libVLC."
grep -Fq -- '-lTaptionFFmpegDecodeBridge' "$RELINK_ROOT/LINK_COMMAND.txt" || \
  fail "Relinking command does not include the Taption FFmpeg bridge."
grep -Fq '${RELINK_ROOT}' "$RELINK_ROOT/LINK_COMMAND.txt" || \
  fail "Relinking command is not rooted in the extracted material directory."
if grep -Fq '/Users/' "$RELINK_ROOT/LINK_COMMAND.txt"; then
  fail "Relinking command contains a packager-specific user path."
fi
grep -Fq 'relinking materials' "$RELINK_ROOT/RELINK_README.txt" || \
  fail "Relinking README does not identify the technical material."
grep -Fq 'The output is unsigned.' "$RELINK_ROOT/RELINK_README.txt" || \
  fail "Relinking README is missing the signing/installation limitation."
tar -tf "$RELINK_ROOT/TaptionEncoder-AppObjects.tar.xz" >"$TEMP_DIR/app-object-members.txt" || \
  fail "Could not read the application object archive."
if ! grep -Eq '\.o$' "$TEMP_DIR/app-object-members.txt"; then
  fail "Application relinking archive contains no .o files."
fi
ARCHIVED_OBJECT_COUNT="$(grep -Ec '\.o$' "$TEMP_DIR/app-object-members.txt")"
[[ "$ARCHIVED_OBJECT_COUNT" == "$RELINK_OBJECT_COUNT" ]] || \
  fail "Relinking object count does not match its metadata."
mkdir -p "$TEMP_DIR/app-objects"
tar -xJf "$RELINK_ROOT/TaptionEncoder-AppObjects.tar.xz" -C "$TEMP_DIR/app-objects" || \
  fail "Could not extract the application object archive."
validated_object_count=0
while IFS= read -r -d '' object_path; do
  file "$object_path" | grep -q 'Mach-O.*object' || \
    fail "Relinking archive contains a non-Mach-O object: $object_path"
  validated_object_count=$((validated_object_count + 1))
done < <(find "$TEMP_DIR/app-objects" -type f -name '*.o' -print0)
[[ "$validated_object_count" == "$RELINK_OBJECT_COUNT" ]] || \
  fail "Validated Mach-O object count does not match relinking metadata."

SOURCE_SHA256="$(shasum -a 256 "$SOURCE_BUNDLE_PATH" | awk '{print $1}')"
RELINK_SHA256="$(shasum -a 256 "$RELINK_BUNDLE_PATH" | awk '{print $1}')"
APP_SIZE_REPORT_SHA256="$(shasum -a 256 "$APP_SIZE_REPORT_PATH" | awk '{print $1}')"
DIST_IPA_SHA256="$(shasum -a 256 "$DIST_IPA_PATH" | awk '{print $1}')"
DIST_IPA_BYTES="$(stat -f '%z' "$DIST_IPA_PATH")"

if [[ "$LEGAL_APPROVAL_REQUIRED" == true ]]; then
  /usr/bin/plutil -convert xml1 -o /dev/null "$LEGAL_APPROVAL_PATH" || \
    fail "Invalid legal approval JSON."
  [[ "$(json_value "$LEGAL_APPROVAL_PATH" status)" == "approved" ]] || fail "Legal status is not approved."
  [[ -n "$(json_value "$LEGAL_APPROVAL_PATH" approvalID)" ]] || fail "Legal approval ID is missing."
  [[ -n "$(json_value "$LEGAL_APPROVAL_PATH" reviewer)" ]] || fail "Legal reviewer is missing."
  [[ "$(json_value "$LEGAL_APPROVAL_PATH" approvedAt)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || \
    fail "Legal approval date must use YYYY-MM-DD."
  [[ "$(json_value "$LEGAL_APPROVAL_PATH" bundleIdentifier)" == "$BUNDLE_ID" ]] || \
    fail "Legal approval bundle identifier does not match."
  [[ "$(json_value "$LEGAL_APPROVAL_PATH" marketingVersion)" == "$MARKETING_VERSION" ]] || \
    fail "Legal approval marketing version does not match."
  [[ "$(json_value "$LEGAL_APPROVAL_PATH" buildVersion)" == "$BUILD_VERSION" ]] || \
    fail "Legal approval build version does not match."
  [[ "$(json_value "$LEGAL_APPROVAL_PATH" sourceBundleSHA256)" == "$SOURCE_SHA256" ]] || \
    fail "Legal approval source-bundle digest does not match."
  [[ "$(json_value "$LEGAL_APPROVAL_PATH" relinkBundleSHA256)" == "$RELINK_SHA256" ]] || \
    fail "Legal approval relink-bundle digest does not match."
  [[ "$(json_value "$LEGAL_APPROVAL_PATH" appSizeReportSHA256)" == "$APP_SIZE_REPORT_SHA256" ]] || \
    fail "Legal approval app-size-report digest does not match."
  [[ "$(json_value "$LEGAL_APPROVAL_PATH" distributionIPASHA256)" == "$DIST_IPA_SHA256" ]] || \
    fail "Legal approval distribution-IPA digest does not match."

  for decision in lgplStaticLinking appStoreEULACarveout libvlcContribMap hevcDistribution; do
    [[ "$(json_value "$LEGAL_APPROVAL_PATH" "$decision")" == "approved" ]] || \
      fail "Legal decision is not approved: $decision"
  done
fi

echo "PUBLIC_DISTRIBUTION_GATE=PASS"
echo "TECHNICAL_RELEASE_CHECKS=PASS"
if [[ "$LEGAL_APPROVAL_REQUIRED" == true ]]; then
  echo "EXTERNAL_LEGAL_APPROVAL=RECORD_VERIFIED"
else
  echo "EXTERNAL_LEGAL_APPROVAL=NOT_REQUIRED_BY_PROJECT_POLICY"
  echo "LEGAL_REVIEW_STATUS=NOT_VERIFIED"
fi
echo "bundleIdentifier=$BUNDLE_ID"
echo "marketingVersion=$MARKETING_VERSION"
echo "buildVersion=$BUILD_VERSION"
echo "uncompressedArchiveAppBytes=$APP_BYTES"
echo "distributionIPABytes=$DIST_IPA_BYTES"
cat "$MACHO_REPORT"
echo "sourceBundleSHA256=$SOURCE_SHA256"
echo "relinkBundleSHA256=$RELINK_SHA256"
echo "appSizeReportSHA256=$APP_SIZE_REPORT_SHA256"
echo "distributionIPASHA256=$DIST_IPA_SHA256"
