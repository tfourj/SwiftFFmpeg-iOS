#!/usr/bin/env bash
# Build the SoX resampler for arm64 iOS devices and simulators.
set -euo pipefail

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

build_soxr_platform() {
  local platform="$1"
  local sdk suffix target prefix codec_build_dir
  sdk=$(xcrun --sdk "$platform" --show-sdk-path)
  suffix=$(get_platform_suffix "$platform")
  target=$(get_target_triple arm64 "$platform")
  prefix="$INSTALL_DIR/arm64-$suffix"
  codec_build_dir="$BUILD_DIR/soxr-arm64-$suffix"
  log_section "Building soxr for arm64 / $platform"

  # soxr 0.1.3 predates CMake 4, which rejects its minimum version without a policy floor.
  cmake -S "$SOXR_SRC_DIR" -B "$codec_build_dir" -G "Unix Makefiles" -Wno-dev \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS_VERSION" \
    -DCMAKE_C_COMPILER="$(xcrun --sdk "$platform" --find clang)" \
    -DCMAKE_C_COMPILER_TARGET="$target" \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF \
    -DWITH_OPENMP=OFF -DWITH_LSR_BINDINGS=OFF
  cmake --build "$codec_build_dir" --parallel "$NUM_JOBS"
  cmake --install "$codec_build_dir"
  test -s "$prefix/lib/libsoxr.a"
}

command -v cmake >/dev/null || { log "Error: install cmake before building soxr"; exit 1; }
download_codec_source "soxr $SOXR_VERSION" \
  "https://downloads.sourceforge.net/project/soxr/soxr-$SOXR_VERSION-Source.tar.xz" \
  "b111c15fdc8c029989330ff559184198c161100a59312f5dc19ddeb9b5a15889" "$SOXR_SRC_DIR"
build_soxr_platform iphoneos
build_soxr_platform iphonesimulator
