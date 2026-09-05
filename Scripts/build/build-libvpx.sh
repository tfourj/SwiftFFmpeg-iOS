#!/usr/bin/env bash
# Build the VP8 and VP9 codecs for arm64 iOS devices and simulators.
set -euo pipefail

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

build_libvpx_platform() (
  local platform="$1"
  local sdk suffix target prefix codec_build_dir cc cxx flags
  sdk=$(xcrun --sdk "$platform" --show-sdk-path)
  suffix=$(get_platform_suffix "$platform")
  target=$(get_target_triple arm64 "$platform")
  prefix="$INSTALL_DIR/arm64-$suffix"
  codec_build_dir="$BUILD_DIR/libvpx-arm64-$suffix"
  cc=$(xcrun --sdk "$platform" --find clang)
  cxx=$(xcrun --sdk "$platform" --find clang++)
  flags="-arch arm64 -target $target -isysroot $sdk"
  mkdir -p "$codec_build_dir"
  cd "$codec_build_dir"
  log_section "Building libvpx for arm64 / $platform"

  # Keep baseline NEON support without assuming newer optional ARM extensions.
  VPX_APPLE_SDK="$platform" VPX_APPLE_TARGET="$target" \
  CC="$cc" CXX="$cxx" LD="$cxx" AS="$cc" \
  AR="$(xcrun --sdk "$platform" --find ar)" \
  STRIP="$(xcrun --sdk "$platform" --find strip)" \
  CFLAGS="$flags" CXXFLAGS="$flags" LDFLAGS="$flags" ASFLAGS="$flags -c" \
    "$LIBVPX_SRC_DIR/configure" \
      --prefix="$prefix" --target=arm64-darwin-gcc \
      --enable-static --disable-shared --enable-pic --enable-vp8 --enable-vp9 \
      --disable-examples --disable-tools --disable-docs --disable-unit-tests \
      --disable-neon-dotprod --disable-neon-i8mm --disable-sve --disable-sve2

  make_with_report -j"$NUM_JOBS"
  make_with_report install
  test -s "$prefix/lib/libvpx.a"
)

download_codec_source "libvpx $LIBVPX_VERSION" \
  "https://github.com/webmproject/libvpx/archive/refs/tags/v$LIBVPX_VERSION.tar.gz" \
  "26fcd3db88045dee380e581862a6ef106f49b74b6396ee95c2993a260b4636aa" "$LIBVPX_SRC_DIR"

# Upstream's arm64 Darwin toolchain hardcodes the device SDK. Make its SDK and
# deployment target explicit without external-build mode (which skips compiling).
python3 - "$LIBVPX_SRC_DIR/build/make/configure.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
replacements = {
    'XCRUN_FIND="xcrun --sdk iphoneos --find"':
        'XCRUN_FIND="xcrun --sdk ${VPX_APPLE_SDK:-iphoneos} --find"',
    'AS="$(${XCRUN_FIND} as)"': 'AS="${CC}"',
    'ASFLAGS="-arch ${tgt_isa} -g"':
        'ASFLAGS="-arch ${tgt_isa} -target ${VPX_APPLE_TARGET} -isysroot '
        '$(show_darwin_sdk_path ${VPX_APPLE_SDK:-iphoneos}) -c"',
    'alt_libc="$(show_darwin_sdk_path iphoneos)"':
        'alt_libc="$(show_darwin_sdk_path ${VPX_APPLE_SDK:-iphoneos})"',
    'add_ldflags -miphoneos-version-min="${IOS_VERSION_MIN}"':
        'add_ldflags -target "${VPX_APPLE_TARGET}"',
}
for old, new in replacements.items():
    if new in source:
        continue
    if source.count(old) != 1:
        raise SystemExit(f"Unexpected libvpx toolchain source: {old}")
    source = source.replace(old, new)
path.write_text(source)
PY

build_libvpx_platform iphoneos
build_libvpx_platform iphonesimulator
