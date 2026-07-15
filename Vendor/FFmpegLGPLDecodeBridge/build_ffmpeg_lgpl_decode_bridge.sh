#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BRIDGE_DIR="$ROOT_DIR/Vendor/FFmpegLGPLDecodeBridge"
SOURCE_DIR="$BRIDGE_DIR/Sources"
OUTPUT_XCFRAMEWORK="${OUTPUT_XCFRAMEWORK:-$BRIDGE_DIR/TaptionFFmpegDecodeBridge.xcframework}"

FFMPEG_VERSION="${FFMPEG_VERSION:-8.1.1}"
FFMPEG_SHA256="${FFMPEG_SHA256:-b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3}"
FFMPEG_URL="${FFMPEG_URL:-https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/build/ffmpeg-lgpl-decode-bridge}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-17.0}"

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
  --disable-shared
  --enable-pic
  --enable-static
  --enable-avcodec
  --enable-avformat
  --enable-avutil
  --enable-swresample
  --enable-swscale
  --enable-protocol=file
  --enable-demuxer=vc1,avi,mov,dv,asf,rm
  --enable-parser=vc1,mpeg4video
  --enable-decoder=vc1,vc1image,y41p,rawvideo,prores_raw,dvvideo,mjpeg,mpeg4,msmpeg4v3,msrle,smc,r10k,r210,rv10,rv20,snow,utvideo,wmv2,pcm_s16le,mp3,aac,ac3,wmav2
)

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

require_file "$SOURCE_DIR/TaptionFFmpegDecodeBridge.c"
require_file "$SOURCE_DIR/TaptionFFmpegDecodeBridge.h"
require_file "$SOURCE_DIR/module.modulemap"

mkdir -p "$WORK_DIR/downloads" "$WORK_DIR/build" "$WORK_DIR/headers"
ARCHIVE_PATH="$WORK_DIR/downloads/ffmpeg-${FFMPEG_VERSION}.tar.xz"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  curl -fL -o "$ARCHIVE_PATH" "$FFMPEG_URL"
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
    "$prefix_path/lib/libswresample.a" \
    "$prefix_path/lib/libswscale.a"
}

rm -rf "$WORK_DIR/headers"
mkdir -p "$WORK_DIR/headers"
cp "$SOURCE_DIR/TaptionFFmpegDecodeBridge.h" "$WORK_DIR/headers/"
cp "$SOURCE_DIR/module.modulemap" "$WORK_DIR/headers/"

build_slice iphoneos iphoneos arm64 -miphoneos-version-min
build_slice iphonesimulator iphonesimulator arm64 -mios-simulator-version-min

rm -rf "$OUTPUT_XCFRAMEWORK"
xcodebuild -create-xcframework \
  -library "$WORK_DIR/build/iphoneos-arm64/libTaptionFFmpegDecodeBridge.a" \
  -headers "$WORK_DIR/headers" \
  -library "$WORK_DIR/build/iphonesimulator-arm64/libTaptionFFmpegDecodeBridge.a" \
  -headers "$WORK_DIR/headers" \
  -output "$OUTPUT_XCFRAMEWORK"

find "$OUTPUT_XCFRAMEWORK" -name '*.a' -type f -print0 | xargs -0 shasum -a 256
