#!/usr/bin/env bash
# Build dav1d AV1 decoding for arm64 iOS devices and simulators.
set -euo pipefail

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

build_dav1d_platform() {
  local platform="$1"
  local sdk suffix target prefix codec_build_dir cross_file
  sdk=$(xcrun --sdk "$platform" --show-sdk-path)
  suffix=$(get_platform_suffix "$platform")
  target=$(get_target_triple arm64 "$platform")
  prefix="$INSTALL_DIR/arm64-$suffix"
  codec_build_dir="$BUILD_DIR/dav1d-arm64-$suffix"
  cross_file="$BUILD_DIR/dav1d-arm64-$suffix.cross"
  log_section "Building dav1d for arm64 / $platform"

  mkdir -p "$BUILD_DIR"
  cat > "$cross_file" <<CROSS
[binaries]
c = '$(xcrun --sdk "$platform" --find clang)'
ar = '$(xcrun --sdk "$platform" --find ar)'
strip = '$(xcrun --sdk "$platform" --find strip)'

[built-in options]
c_args = ['-arch', 'arm64', '-target', '$target', '-isysroot', '$sdk']
c_link_args = ['-arch', 'arm64', '-target', '$target', '-isysroot', '$sdk']

[host_machine]
system = 'darwin'
subsystem = 'ios'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
CROSS

  rm -rf "$codec_build_dir"
  meson setup "$codec_build_dir" "$DAV1D_SRC_DIR" --cross-file "$cross_file" \
    --prefix="$prefix" --libdir=lib --buildtype=release --default-library=static \
    -Db_pie=true -Denable_tools=false -Denable_examples=false -Denable_tests=false \
    -Denable_docs=false
  meson compile -C "$codec_build_dir" -j "$NUM_JOBS"
  meson install -C "$codec_build_dir"
  test -s "$prefix/lib/libdav1d.a"
}

command -v meson >/dev/null || { log "Error: install meson and ninja before building dav1d"; exit 1; }
command -v ninja >/dev/null || { log "Error: install meson and ninja before building dav1d"; exit 1; }
download_codec_source "dav1d $DAV1D_VERSION" \
  "https://downloads.videolan.org/pub/videolan/dav1d/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.xz" \
  "686616b7c69eb88d44459391ab25cac13b6647a3b288835c5784e71c1514a5c5" "$DAV1D_SRC_DIR"
build_dav1d_platform iphoneos
build_dav1d_platform iphonesimulator
