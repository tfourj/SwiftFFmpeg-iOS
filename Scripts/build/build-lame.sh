#!/usr/bin/env bash
# Build LAME (libmp3lame) for iOS
set -e

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

# Download LAME if not present
download_lame() {
  if [ -f "$LAME_SRC_DIR/configure" ]; then
    log "LAME source already present"
    return 0
  fi
  
  log_section "Downloading LAME source"
  cd "$PROJECT_ROOT"
  
  if command -v git &> /dev/null; then
    git clone --depth 1 https://github.com/gypified/lame.git lame || {
      log "Failed to clone LAME. Trying alternative method..."
      LAME_VERSION="3.100"
      curl -L "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" -o lame.tar.gz
      tar -xzf lame.tar.gz
      mv "lame-${LAME_VERSION}" lame
      rm lame.tar.gz
    }
  else
    log "Error: git is not installed"
    exit 1
  fi
  
  if [ ! -f "$LAME_SRC_DIR/configure" ]; then
    log "Error: Failed to obtain LAME source"
    exit 1
  fi
}

# Build LAME for a specific architecture
build_lame_arch() {
  local ARCH=$1
  local PLATFORM=$2
  
  log_section "Building LAME for $ARCH / $PLATFORM"
  
  local SDK
  SDK=$(xcrun --sdk "$PLATFORM" --show-sdk-path)
  
  local PLATFORM_SUFFIX=$(get_platform_suffix "$PLATFORM")
  local TARGET_TRIPLE=$(get_target_triple "$ARCH" "$PLATFORM")
  
  local PREFIX="$INSTALL_DIR/${ARCH}-${PLATFORM_SUFFIX}"
  local LAME_BUILD_DIR="$BUILD_DIR/lame-${ARCH}-${PLATFORM_SUFFIX}"
  
  mkdir -p "$LAME_BUILD_DIR"
  cd "$LAME_BUILD_DIR"
  
  local CC="$(xcrun --sdk $PLATFORM -f clang)"
  local FULL_CC="$CC -arch $ARCH -isysroot $SDK -mios-version-min=$MIN_IOS_VERSION -target $TARGET_TRIPLE"
  
  # Host triple for autotools
  local HOST_TRIPLE="arm-apple-darwin"
  if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "i386" ]; then
    HOST_TRIPLE="x86_64-apple-darwin"
  fi
  
  # Set environment variables for cross-compilation
  export ac_cv_c_bigendian=no
  export ac_cv_func_malloc_0_nonnull=yes
  export ac_cv_func_realloc_0_nonnull=yes
  
  "$LAME_SRC_DIR/configure" \
    --prefix="$PREFIX" \
    --host="$HOST_TRIPLE" \
    --build=x86_64-apple-darwin \
    --disable-shared \
    --enable-static \
    --disable-frontend \
    --disable-decoder \
    CC="$FULL_CC" \
    CXX="$FULL_CC" \
    CFLAGS="-arch $ARCH -isysroot $SDK -mios-version-min=$MIN_IOS_VERSION -target $TARGET_TRIPLE" \
    CXXFLAGS="-arch $ARCH -isysroot $SDK -mios-version-min=$MIN_IOS_VERSION -target $TARGET_TRIPLE" \
    LDFLAGS="-arch $ARCH -isysroot $SDK -mios-version-min=$MIN_IOS_VERSION -target $TARGET_TRIPLE"
  
  make_with_report -j"$NUM_JOBS"
  make_with_report install
  
  log "LAME built successfully for $ARCH / $PLATFORM"
}

# Main execution
main() {
  download_lame
  
  # Build for device and simulator
  build_lame_arch arm64 iphoneos
  build_lame_arch arm64 iphonesimulator
  
  log_section "LAME build complete"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

