#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

OUTPUT_PATH=""
OBJECTS_DIR=""
LINK_FILE_LIST=""
DEPENDENCY_INFO_PATH=""
ACTIVITY_LOG_PATH=""
MARKETING_VERSION=""
BUILD_VERSION=""

usage() {
  cat >&2 <<EOF
Usage: $0 \
  --output FILE.tar.xz \
  --objects-dir Objects-normal/arm64 \
  --link-file-list "Taption Encoder.LinkFileList" \
  --dependency-info "Taption Encoder_dependency_info.dat" \
  --activity-log Release.xcactivitylog \
  --marketing-version VERSION \
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
    --objects-dir)
      [[ $# -ge 2 ]] || usage
      OBJECTS_DIR="$2"
      shift 2
      ;;
    --link-file-list)
      [[ $# -ge 2 ]] || usage
      LINK_FILE_LIST="$2"
      shift 2
      ;;
    --dependency-info)
      [[ $# -ge 2 ]] || usage
      DEPENDENCY_INFO_PATH="$2"
      shift 2
      ;;
    --activity-log)
      [[ $# -ge 2 ]] || usage
      ACTIVITY_LOG_PATH="$2"
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
[[ -d "$OBJECTS_DIR" ]] || usage
[[ -f "$LINK_FILE_LIST" ]] || usage
[[ -f "$DEPENDENCY_INFO_PATH" ]] || usage
[[ -f "$ACTIVITY_LOG_PATH" ]] || usage
[[ -n "$MARKETING_VERSION" ]] || usage
[[ -n "$BUILD_VERSION" ]] || usage
[[ -f "$ROOT_DIR/TaptionEncoder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" ]] || {
  echo "Missing release Package.resolved." >&2
  exit 1
}

mkdir -p "$(dirname "$OUTPUT_PATH")"
OUTPUT_PATH="$(cd "$(dirname "$OUTPUT_PATH")" && pwd -P)/$(basename "$OUTPUT_PATH")"
OBJECTS_DIR="$(cd "$OBJECTS_DIR" && pwd -P)"
LINK_FILE_LIST="$(cd "$(dirname "$LINK_FILE_LIST")" && pwd -P)/$(basename "$LINK_FILE_LIST")"
DEPENDENCY_INFO_PATH="$(cd "$(dirname "$DEPENDENCY_INFO_PATH")" && pwd -P)/$(basename "$DEPENDENCY_INFO_PATH")"
ACTIVITY_LOG_PATH="$(cd "$(dirname "$ACTIVITY_LOG_PATH")" && pwd -P)/$(basename "$ACTIVITY_LOG_PATH")"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/taption-relink-materials.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
STAGE_DIR="$TEMP_DIR/TaptionEncoder-${MARKETING_VERSION}-${BUILD_VERSION}-RelinkMaterials"
APP_OBJECTS_DIR="$STAGE_DIR/AppObjects"
mkdir -p "$APP_OBJECTS_DIR"

RAW_ACTIVITY_LOG="$TEMP_DIR/release.xcactivitylog.raw"
if gzip -t "$ACTIVITY_LOG_PATH" 2>/dev/null; then
  gzip -dc "$ACTIVITY_LOG_PATH" >"$RAW_ACTIVITY_LOG"
else
  cp "$ACTIVITY_LOG_PATH" "$RAW_ACTIVITY_LOG"
fi

RAW_LINK_COMMAND="$TEMP_DIR/link-command.raw.txt"
perl -0777 -ne '
  while (m{(/Applications/Xcode\.app/Contents/Developer/Toolchains/[^\r]+/clang\s+[^\r]+)}g) {
    my $command = $1;
    if (index($command, "-lvlc") >= 0 &&
        index($command, "-lTaptionFFmpegDecodeBridge") >= 0 &&
        index($command, "Taption\\ Encoder.app/Taption\\ Encoder") >= 0) {
      print $command, "\n";
      exit 0;
    }
  }
  exit 1;
' "$RAW_ACTIVITY_LOG" >"$RAW_LINK_COMMAND" || {
  echo "Could not extract the Taption Encoder release link command." >&2
  exit 1
}

grep -Fq -- "-lvlc" "$RAW_LINK_COMMAND" || {
  echo "The release link command does not contain libVLC." >&2
  exit 1
}
grep -Fq -- "-lTaptionFFmpegDecodeBridge" "$RAW_LINK_COMMAND" || {
  echo "The release link command does not contain the Taption FFmpeg bridge." >&2
  exit 1
}

object_count=0
: >"$STAGE_DIR/Taption Encoder.LinkFileList"
while IFS= read -r object_path || [[ -n "$object_path" ]]; do
  [[ "$object_path" == *.o ]] || {
    echo "Unexpected non-object entry in link file list: $object_path" >&2
    exit 1
  }
  [[ -f "$object_path" ]] || {
    echo "Missing release object: $object_path" >&2
    exit 1
  }
  file "$object_path" | grep -q 'Mach-O.*object' || {
    echo "Release input is not a Mach-O object: $object_path" >&2
    exit 1
  }

  object_name="$(basename "$object_path")"
  [[ ! -e "$APP_OBJECTS_DIR/$object_name" ]] || {
    echo "Duplicate release object basename: $object_name" >&2
    exit 1
  }
  cp "$object_path" "$APP_OBJECTS_DIR/$object_name"
  printf 'AppObjects/%s\n' "$object_name" >>"$STAGE_DIR/Taption Encoder.LinkFileList"
  object_count=$((object_count + 1))
done <"$LINK_FILE_LIST"

[[ "$object_count" -gt 0 ]] || {
  echo "No release application objects were collected." >&2
  exit 1
}

cp "$ROOT_DIR/TaptionEncoder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
  "$STAGE_DIR/Package.resolved"

xcode_version="$(xcodebuild -version | paste -sd ' ' -)"
sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
sdk_name="$(xcrun --sdk iphoneos --show-sdk-platform-version)"
toolchain_clang="$(xcrun --sdk iphoneos --find clang)"

export RAW_LINK_COMMAND OBJECTS_DIR LINK_FILE_LIST DEPENDENCY_INFO_PATH
export STAGE_DIR sdk_path toolchain_clang
perl -MText::ParseWords=shellwords -0777 -ne '
  my @tokens = shellwords($_);
  my @result;
  my $skip = 0;

  for (my $index = 0; $index < @tokens; $index++) {
    if ($index + 3 < @tokens &&
        $tokens[$index] eq "-Xlinker" &&
        $tokens[$index + 1] eq "-add_ast_path" &&
        $tokens[$index + 2] eq "-Xlinker") {
      $index += 3;
      next;
    }
    next if $tokens[$index] =~ /^\@.*\.resp$/;

    my $token = $tokens[$index];
    $token =~ s{^/tmp/}{/private/tmp/};
    if ($token eq $ENV{toolchain_clang}) {
      push @result, q{"${TOOLCHAIN_CLANG}"};
    } elsif ($token eq $ENV{sdk_path}) {
      push @result, q{"${SDKROOT}"};
    } elsif ($token eq $ENV{LINK_FILE_LIST}) {
      push @result, q{"${RELINK_ROOT}/Taption Encoder.LinkFileList"};
    } elsif ($token eq "-o" && $index + 1 < @tokens) {
      push @result, "-o", q{"${OUTPUT_EXECUTABLE}"};
      $index++;
    } elsif ($token =~ m{/Objects-normal/arm64/Taption Encoder_lto\.o$}) {
      push @result, q{"${RELINK_WORK_DIR}/Taption Encoder_lto.o"};
    } elsif ($token eq $ENV{DEPENDENCY_INFO_PATH}) {
      push @result, q{"${RELINK_WORK_DIR}/Taption Encoder_dependency_info.dat"};
    } elsif ($token =~ m{^-([LF])(.*/ArchiveIntermediates/TaptionEncoder)/IntermediateBuildFilesPath/EagerLinkingTBDs/Release-iphoneos$}) {
      push @result, "-$1\"\${EAGER_LINKING_TBDS_DIR}\"";
    } elsif ($token =~ m{^-([LF])(.*/ArchiveIntermediates/TaptionEncoder)/BuildProductsPath/Release-iphoneos/PackageFrameworks$}) {
      push @result, "-$1\"\${PACKAGE_FRAMEWORKS_DIR}\"";
    } elsif ($token =~ m{^-([LF])(.*/ArchiveIntermediates/TaptionEncoder)/BuildProductsPath/Release-iphoneos$}) {
      push @result, "-$1\"\${BUILD_PRODUCTS_DIR}\"";
    } elsif (index($token, "/Users/") >= 0 || index($token, "/private/tmp/") >= 0) {
      die "Unnormalized user-specific path in link command: $token\n";
    } else {
      $token =~ s/\x27/\x27\"\x27\"\x27/g;
      push @result, "\x27$token\x27";
    }
  }

  print "#!/usr/bin/env bash\n";
  print "set -euo pipefail\n\n";
  print q{: "${RELINK_ROOT:?Set RELINK_ROOT to the extracted relink-material directory}"}, "\n";
  print q{: "${BUILD_PRODUCTS_DIR:?Provide rebuilt libvlc, FFmpeg bridge, and pinned package frameworks}"}, "\n";
  print q{PACKAGE_FRAMEWORKS_DIR="${PACKAGE_FRAMEWORKS_DIR:-${BUILD_PRODUCTS_DIR}/PackageFrameworks}"}, "\n";
  print q{EAGER_LINKING_TBDS_DIR="${EAGER_LINKING_TBDS_DIR:-${BUILD_PRODUCTS_DIR}}"}, "\n";
  print q{RELINK_WORK_DIR="${RELINK_WORK_DIR:-${RELINK_ROOT}/RelinkWork}"}, "\n";
  print q{OUTPUT_EXECUTABLE="${OUTPUT_EXECUTABLE:-${RELINK_WORK_DIR}/Taption Encoder}"}, "\n";
  print q{TOOLCHAIN_CLANG="${TOOLCHAIN_CLANG:-$(xcrun --sdk iphoneos --find clang)}"}, "\n";
  print q{SDKROOT="${SDKROOT:-$(xcrun --sdk iphoneos --show-sdk-path)}"}, "\n";
  print q{mkdir -p "${RELINK_WORK_DIR}"}, "\n";
  print q{cd "${RELINK_ROOT}"}, "\n\n";
  print join(" \\\n  ", @result), "\n";
' "$RAW_LINK_COMMAND" >"$STAGE_DIR/LINK_COMMAND.txt"

if grep -Fq '/Users/' "$STAGE_DIR/LINK_COMMAND.txt"; then
  echo "Generated link command contains a user-specific path." >&2
  exit 1
fi

{
  echo "Release toolchain: $xcode_version"
  echo "iPhoneOS SDK platform version: $sdk_name"
  echo "iPhoneOS SDK path at packaging time: $sdk_path"
  echo "Target: arm64-apple-ios18.0"
  echo
  echo "Link flags from the archived application command:"
  perl -MText::ParseWords=shellwords -0777 -ne '
    my %seen;
    for my $token (shellwords($_)) {
      if ($token eq "-framework") {
        $want_framework = 1;
        next;
      }
      if ($want_framework) {
        $seen{"framework $token"} = 1;
        $want_framework = 0;
        next;
      }
      $seen{$token} = 1 if $token =~ /^-l[A-Za-z0-9_+]+$/;
    }
    print "$_\n" for sort keys %seen;
  ' "$RAW_LINK_COMMAND"
  echo
  echo "System SDK and toolchain inputs recorded by ld:"
  strings "$DEPENDENCY_INFO_PATH" |
    grep -E '^/Applications/Xcode\.app/.*\.(tbd|a)$' |
    sed 's#^/Applications/Xcode\.app#${XCODE_APP}#' |
    LC_ALL=C sort -u
} >"$STAGE_DIR/SYSTEM_LINK_INPUTS.txt"

cat >"$STAGE_DIR/RELINK_README.txt" <<EOF
Taption Encoder ${MARKETING_VERSION} (${BUILD_VERSION}) relinking materials

Status: TECHNICAL RELINK MATERIALS - NOT A LEGAL APPROVAL

This package contains the Mach-O object files selected by the archived app's
LinkFileList and a normalized form of the archived clang link command. It does
not assert that App Store delivery, Apple code signing, or this material set
satisfies LGPL 2.1. License compliance remains the distributor's responsibility;
any legal assessment is separate from this technical material.

The package was captured with ${xcode_version}, iPhoneOS SDK ${sdk_name}, for
arm64-apple-ios18.0. The normalized link command omits add_ast_path arguments;
those arguments carry compiler AST metadata and are not executable link input.

To perform the technical relink:

1. Extract TaptionEncoder-AppObjects.tar.xz into this directory. It creates the
   AppObjects directory referenced by Taption Encoder.LinkFileList.
2. Build a replacement libvlc.a from the pinned source bundle. Build the narrow
   Taption FFmpeg bridge from its included source and recipe. Resolve the exact
   Package.resolved dependencies for GoogleMobileAds 13.5.0 and
   UserMessagingPlatform 3.1.0.
3. Place libvlc.a, libTaptionFFmpegDecodeBridge.a, GoogleMobileAds.framework,
   and UserMessagingPlatform.framework in one BUILD_PRODUCTS_DIR. If package
   frameworks are stored separately, set PACKAGE_FRAMEWORKS_DIR.
4. Run LINK_COMMAND.txt with bash after setting RELINK_ROOT and
   BUILD_PRODUCTS_DIR. The output is unsigned. Signing and installation require
   the relinker's own Apple-authorized identity and provisioning environment.

The original proprietary Swift source is not included. The application object
files are provided only as the release-specific technical relinking input.
Keep this package digest bound to the matching source bundle, distribution IPA,
App Thinning report, and release record. External approval may be recorded
separately if an actual review is obtained; it is not a mandatory gate input.
EOF

cat >"$STAGE_DIR/relink-metadata.json" <<EOF
{
  "schemaVersion": 1,
  "technicalStatus": "technical-relink-materials",
  "bundleIdentifier": "com.taption.encoder",
  "marketingVersion": "$MARKETING_VERSION",
  "buildVersion": "$BUILD_VERSION",
  "architecture": "arm64",
  "minimumOS": "18.0",
  "objectCount": $object_count,
  "xcodeVersion": "$xcode_version",
  "sdkPlatformVersion": "$sdk_name"
}
EOF

find "$APP_OBJECTS_DIR" -exec touch -h -t 202607140000 {} +
COPYFILE_DISABLE=1 tar -cJf "$STAGE_DIR/TaptionEncoder-AppObjects.tar.xz" \
  -C "$STAGE_DIR" AppObjects
rm -rf "$APP_OBJECTS_DIR"

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

echo "objectCount=$object_count"
shasum -a 256 "$OUTPUT_PATH"
