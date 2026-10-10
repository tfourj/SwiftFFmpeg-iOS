#!/usr/bin/env bash
# Build WebP image encoding for arm64 iOS devices and simulators.
set -euo pipefail

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

build_libwebp_platform() {
  local platform="$1"
  local sdk suffix target prefix codec_build_dir
  sdk=$(xcrun --sdk "$platform" --show-sdk-path)
  suffix=$(get_platform_suffix "$platform")
  target=$(get_target_triple arm64 "$platform")
  prefix="$INSTALL_DIR/arm64-$suffix"
  codec_build_dir="$BUILD_DIR/libwebp-arm64-$suffix"
  log_section "Building libwebp for arm64 / $platform"

  # Only the libraries are needed; libwebpmux provides FFmpeg's animated encoder.
  cmake -S "$LIBWEBP_SRC_DIR" -B "$codec_build_dir" -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS_VERSION" \
    -DCMAKE_C_COMPILER="$(xcrun --sdk "$platform" --find clang)" \
    -DCMAKE_C_COMPILER_TARGET="$target" \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF \
    -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF \
    -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF \
    -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_LIBWEBPMUX=ON
  cmake --build "$codec_build_dir" --parallel "$NUM_JOBS"
  cmake --install "$codec_build_dir"
  test -s "$prefix/lib/libwebp.a"
  test -s "$prefix/lib/libwebpmux.a"
}

command -v cmake >/dev/null || { log "Error: install cmake before building libwebp"; exit 1; }
download_codec_source "libwebp $LIBWEBP_VERSION" \
  "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$LIBWEBP_VERSION.tar.gz" \
  "e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564" "$LIBWEBP_SRC_DIR"
build_libwebp_platform iphoneos
build_libwebp_platform iphonesimulator
