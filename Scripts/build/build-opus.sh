#!/usr/bin/env bash
# Build Opus audio encoding for arm64 iOS devices and simulators.
set -euo pipefail

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

build_opus_platform() {
  local platform="$1"
  local sdk suffix target prefix codec_build_dir
  sdk=$(xcrun --sdk "$platform" --show-sdk-path)
  suffix=$(get_platform_suffix "$platform")
  target=$(get_target_triple arm64 "$platform")
  prefix="$INSTALL_DIR/arm64-$suffix"
  codec_build_dir="$BUILD_DIR/opus-arm64-$suffix"
  log_section "Building Opus for arm64 / $platform"

  cmake -S "$OPUS_SRC_DIR" -B "$codec_build_dir" -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS_VERSION" \
    -DCMAKE_C_COMPILER="$(xcrun --sdk "$platform" --find clang)" \
    -DCMAKE_C_COMPILER_TARGET="$target" \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF -DOPUS_BUILD_TESTING=OFF -DOPUS_BUILD_PROGRAMS=OFF \
    -DOPUS_INSTALL_PKG_CONFIG_MODULE=ON
  cmake --build "$codec_build_dir" --parallel "$NUM_JOBS"
  cmake --install "$codec_build_dir"
  test -s "$prefix/lib/libopus.a"
}

command -v cmake >/dev/null || { log "Error: install cmake before building Opus"; exit 1; }
download_codec_source "Opus $OPUS_VERSION" \
  "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz" \
  "65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1" "$OPUS_SRC_DIR"
build_opus_platform iphoneos
build_opus_platform iphonesimulator
