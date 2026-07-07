#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_DIR="$ROOT_DIR/Vendor/FFmpegLGPLDecodeBridge"
SOURCE_DIR="$BRIDGE_DIR/Sources"
OUTPUT_XCFRAMEWORK="$BRIDGE_DIR/TaptionFFmpegDecodeBridge.xcframework"

FFMPEG_VERSION="${FFMPEG_VERSION:-8.1.1}"
FFMPEG_SHA256="${FFMPEG_SHA256:-b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3}"
FFMPEG_URL="${FFMPEG_URL:-https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/build/ffmpeg-lgpl-decode-bridge}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-17.0}"

if [[ ! -f "$SOURCE_DIR/TaptionFFmpegDecodeBridge.c" ]]; then
  echo "Missing bridge source: $SOURCE_DIR/TaptionFFmpegDecodeBridge.c" >&2
  exit 1
fi

mkdir -p "$WORK_DIR/downloads" "$WORK_DIR/build" "$WORK_DIR/headers"
ARCHIVE_PATH="$WORK_DIR/downloads/ffmpeg-${FFMPEG_VERSION}.tar.xz"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  curl -L --fail -o "$ARCHIVE_PATH" "$FFMPEG_URL"
fi

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$FFMPEG_SHA256" ]]; then
  echo "FFmpeg archive SHA-256 mismatch." >&2
  echo "expected: $FFMPEG_SHA256" >&2
  echo "actual:   $ACTUAL_SHA256" >&2
  exit 1
fi

rm -rf "$WORK_DIR/src"
mkdir -p "$WORK_DIR/src"
tar -xJf "$ARCHIVE_PATH" -C "$WORK_DIR/src"

COMMON_CONFIGURE_FLAGS=(
  --disable-everything
  --disable-programs
  --disable-doc
  --disable-debug
  --disable-network
  --disable-autodetect
  --disable-asm
  --disable-avdevice
  --disable-avfilter
  --disable-swresample
  --disable-shared
  --enable-pic
  --enable-static
  --enable-avcodec
  --enable-avformat
  --enable-avutil
  --enable-swscale
  --enable-protocol=file
  --enable-demuxer=vc1,avi
  --enable-parser=vc1
  --enable-decoder=vc1,vc1image,y41p,rawvideo,pcm_s16le
)

build_slice() {
  local platform="$1"
  local sdk="$2"
  local arch="$3"
  local min_flag="$4"
  local source_path="$WORK_DIR/src/ffmpeg-${FFMPEG_VERSION}"
  local build_path="$WORK_DIR/build/$platform-$arch"
  local prefix_path="$build_path/prefix"
  local sdk_path
  local cc

  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cc="$(xcrun --sdk "$sdk" -f clang)"

  rm -rf "$build_path"
  mkdir -p "$build_path"
  cp -R "$source_path/." "$build_path/source"

  pushd "$build_path/source" >/dev/null
  ./configure \
    --prefix="$prefix_path" \
    --target-os=darwin \
    --arch="$arch" \
    --cc="$cc" \
    --sysroot="$sdk_path" \
    --enable-cross-compile \
    --extra-cflags="-arch $arch $min_flag=$MIN_IOS_VERSION -isysroot $sdk_path" \
    --extra-ldflags="-arch $arch $min_flag=$MIN_IOS_VERSION -isysroot $sdk_path" \
    "${COMMON_CONFIGURE_FLAGS[@]}"
  make -j"$(sysctl -n hw.logicalcpu)"
  make install
  popd >/dev/null

  local object_path="$build_path/TaptionFFmpegDecodeBridge.o"
  "$cc" \
    -arch "$arch" \
    "$min_flag=$MIN_IOS_VERSION" \
    -isysroot "$sdk_path" \
    -I"$prefix_path/include" \
    -I"$SOURCE_DIR" \
    -fPIC \
    -c "$SOURCE_DIR/TaptionFFmpegDecodeBridge.c" \
    -o "$object_path"

  xcrun libtool -static \
    -o "$build_path/libTaptionFFmpegDecodeBridge.a" \
    "$object_path" \
    "$prefix_path/lib/libavformat.a" \
    "$prefix_path/lib/libavcodec.a" \
    "$prefix_path/lib/libavutil.a" \
    "$prefix_path/lib/libswscale.a"
}

rm -rf "$WORK_DIR/headers"
mkdir -p "$WORK_DIR/headers"
cp "$SOURCE_DIR/TaptionFFmpegDecodeBridge.h" "$WORK_DIR/headers/"
cp "$SOURCE_DIR/module.modulemap" "$WORK_DIR/headers/"

build_slice "iphoneos" "iphoneos" "arm64" "-miphoneos-version-min"
build_slice "iphonesimulator" "iphonesimulator" "arm64" "-mios-simulator-version-min"

rm -rf "$OUTPUT_XCFRAMEWORK"
xcodebuild -create-xcframework \
  -library "$WORK_DIR/build/iphoneos-arm64/libTaptionFFmpegDecodeBridge.a" \
  -headers "$WORK_DIR/headers" \
  -library "$WORK_DIR/build/iphonesimulator-arm64/libTaptionFFmpegDecodeBridge.a" \
  -headers "$WORK_DIR/headers" \
  -output "$OUTPUT_XCFRAMEWORK"

cat >"$BRIDGE_DIR/FFMPEG_LGPL_DECODE_BRIDGE_BUILD.txt" <<EOF
FFmpeg version: ${FFMPEG_VERSION}
FFmpeg source: ${FFMPEG_URL}
FFmpeg SHA-256: ${FFMPEG_SHA256}
Minimum iOS: ${MIN_IOS_VERSION}

Configure flags:
$(printf '  %s\n' "${COMMON_CONFIGURE_FLAGS[@]}")

Enabled demuxers: vc1, avi
Enabled decoders: vc1, vc1image, y41p, rawvideo, pcm_s16le
Enabled parser: vc1
Enabled protocol: file
Enabled libraries linked into bridge: avformat, avcodec, avutil, swscale

Policy:
- No --enable-gpl
- No --enable-nonfree
- No external libraries
- No FFmpeg executable or runtime-downloaded plugin
- Decode-only bridge; H.265 / HEVC MP4/MOV output remains handled by Taption Encoder's AVAssetWriter path.

Notice/source/EULA checklist:
- Source availability is pinned to the official source URL and SHA-256 above.
- Local bridge source is stored under Vendor/FFmpegLGPLDecodeBridge/Sources.
- Open-source notice draft is stored at TaptionEncoder/OpenSourceNotices/FFmpeg-LGPL-Decode-Bridge.txt.
- Formal counsel approval, final release EULA language, and any LGPL relinking/reverse-engineering obligations remain separate release gates.
EOF

du -sh "$OUTPUT_XCFRAMEWORK"
