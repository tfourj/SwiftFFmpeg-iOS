#!/usr/bin/env bash
# Build FFmpeg for iOS
set -e

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

# Download FFmpeg if not present
download_ffmpeg() {
  if [ -f "$FFMPEG_SRC_DIR/configure" ]; then
    log "FFmpeg source already present"
    return 0
  fi
  
  log_section "Downloading FFmpeg source"
  cd "$PROJECT_ROOT"
  
  if command -v git &> /dev/null; then
    git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git ffmpeg || {
      log "Failed to clone FFmpeg. Trying alternative method..."
      FFMPEG_VERSION="7.0"
      curl -L "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${FFMPEG_VERSION}.tar.gz" -o ffmpeg.tar.gz
      tar -xzf ffmpeg.tar.gz
      mv "FFmpeg-n${FFMPEG_VERSION}" ffmpeg
      rm ffmpeg.tar.gz
    }
  else
    log "Error: git is not installed"
    exit 1
  fi
  
  if [ ! -f "$FFMPEG_SRC_DIR/configure" ]; then
    log "Error: Failed to obtain FFmpeg source"
    exit 1
  fi
}

# Build FFmpeg for a specific architecture
build_ffmpeg_arch() {
  local ARCH=$1
  local PLATFORM=$2

  log_section "Building FFmpeg for $ARCH / $PLATFORM"

  local SDK
  SDK=$(xcrun --sdk "$PLATFORM" --show-sdk-path)

  local PLATFORM_SUFFIX=$(get_platform_suffix "$PLATFORM")
  local TARGET_TRIPLE=$(get_target_triple "$ARCH" "$PLATFORM")
  
  local PREFIX="$INSTALL_DIR/${ARCH}-${PLATFORM_SUFFIX}"
  local BUILD_SUBDIR="${ARCH}-${PLATFORM_SUFFIX}"
  
  mkdir -p "$BUILD_DIR/$BUILD_SUBDIR"
  cd "$BUILD_DIR/$BUILD_SUBDIR"

  local CC="$(xcrun --sdk $PLATFORM -f clang)"
  
  # LAME paths
  local LAME_PREFIX="$INSTALL_DIR/${ARCH}-${PLATFORM_SUFFIX}"
  local LAME_CFLAGS="-I$LAME_PREFIX/include"
  local LAME_LDFLAGS="-L$LAME_PREFIX/lib"
  
  PKG_CONFIG_PATH="" \
  CFLAGS="-arch $ARCH -isysroot $SDK -mios-version-min=$MIN_IOS_VERSION -target $TARGET_TRIPLE $LAME_CFLAGS" \
  LDFLAGS="-arch $ARCH -isysroot $SDK -mios-version-min=$MIN_IOS_VERSION -target $TARGET_TRIPLE $LAME_LDFLAGS -lpthread" \
  "$FFMPEG_SRC_DIR/configure" \
    --prefix="$PREFIX" \
    "${COMMON_FFMPEG_FLAGS[@]}" \
    --target-os=darwin \
    --arch="$ARCH" \
    --enable-cross-compile \
    --cc="$CC -target $TARGET_TRIPLE" \
    --extra-cflags="$LAME_CFLAGS" \
    --extra-ldflags="$LAME_LDFLAGS -lpthread"

  make_with_report -j"$NUM_JOBS"
  make_with_report install

  # Build CLI library
  build_cli_library "$ARCH" "$PLATFORM" "$PREFIX" "$BUILD_SUBDIR" "$SDK" "$TARGET_TRIPLE" "$CC"
  
  log "FFmpeg built successfully for $ARCH / $PLATFORM"
}

# Build libffmpeg_cli.a (CLI shim library)
build_cli_library() {
  local ARCH=$1
  local PLATFORM=$2
  local PREFIX=$3
  local BUILD_SUBDIR=$4
  local SDK=$5
  local TARGET_TRIPLE=$6
  local CC=$7

  log "Building libffmpeg_cli.a (CLI shim) for $ARCH / $PLATFORM"

  cd "$BUILD_DIR/$BUILD_SUBDIR"
  
  # Find all fftools object files
  local FFTOOLS_OBJS=$(find . -path "*/fftools/*.o" -type f 2>/dev/null)
  
  if [ -z "$FFTOOLS_OBJS" ]; then
    log "No fftools object files found, trying to build..."
    make -j"$NUM_JOBS" 2>/dev/null || true
    FFTOOLS_OBJS=$(find . -path "*/fftools/*.o" -type f 2>/dev/null)
  fi
  
  if [ -z "$FFTOOLS_OBJS" ]; then
    log "Error: Could not find or build fftools object files"
    exit 1
  fi
  
  log "Found $(echo "$FFTOOLS_OBJS" | wc -l | tr -d ' ') fftools object files"
  
  # Create temporary directory for processing
  local TEMP_DIR=$(mktemp -d)
  
  # Copy all fftools object files except ffmpeg.o and ffprobe.o
  for obj in $FFTOOLS_OBJS; do
    local basename_obj=$(basename "$obj")
    if [ "$basename_obj" != "ffmpeg.o" ] && [ "$basename_obj" != "ffprobe.o" ]; then
      cp "$obj" "$TEMP_DIR/$basename_obj"
    fi
  done
  
  # Get compiler from config if available
  local COMPILER="$CC"
  if [ -f "config.mak" ]; then
    local CONFIG_CC=$(grep "^CC=" config.mak | sed 's/^CC=//' | sed "s/'//g" | head -1)
    if [ -n "$CONFIG_CC" ]; then
      COMPILER="$CONFIG_CC"
    fi
  fi
  
  # Common compiler flags
  local COMMON_COMPILE_FLAGS=(
    -arch "$ARCH"
    -isysroot "$SDK"
    -mios-version-min="$MIN_IOS_VERSION"
    -target "$TARGET_TRIPLE"
    -I"$BUILD_DIR/$BUILD_SUBDIR"
    -I"$BUILD_DIR/$BUILD_SUBDIR/fftools"
    -I"$PREFIX/include"
    -I"$FFMPEG_SRC_DIR"
    -I"$FFMPEG_SRC_DIR/fftools"
  )
  
  # Recompile ffmpeg.c with main renamed
  log "Recompiling ffmpeg.c..."
  $COMPILER "${COMMON_COMPILE_FLAGS[@]}" \
    -c "$FFMPEG_SRC_DIR/fftools/ffmpeg.c" -o "$TEMP_DIR/ffmpeg.o" \
    -Dmain=ffmpeg_main
  
  if [ ! -f "$TEMP_DIR/ffmpeg.o" ]; then
    log "Error: Failed to compile ffmpeg.c"
    rm -rf "$TEMP_DIR"
    exit 1
  fi
  
  # Recompile ffprobe.c with main renamed
  if [ -f "$FFMPEG_SRC_DIR/fftools/ffprobe.c" ]; then
    log "Recompiling ffprobe.c..."
    $COMPILER "${COMMON_COMPILE_FLAGS[@]}" \
      -c "$FFMPEG_SRC_DIR/fftools/ffprobe.c" -o "$TEMP_DIR/ffprobe.o" \
      -Dmain=ffprobe_main
    
    if [ ! -f "$TEMP_DIR/ffprobe.o" ]; then
      log "Warning: Failed to compile ffprobe.c"
    fi
  fi
  
  # Create the static library
  ar rcs "$PREFIX/lib/libffmpeg_cli.a" "$TEMP_DIR"/*.o
  
  rm -rf "$TEMP_DIR"
  log "libffmpeg_cli.a created successfully"
}

# Main execution
main() {
  download_ffmpeg
  
  # Apply patches before building
  "$BUILD_SCRIPT_DIR/apply-patches.sh"
  
  # Build for device and simulator
  build_ffmpeg_arch arm64 iphoneos
  build_ffmpeg_arch arm64 iphonesimulator
  
  log_section "FFmpeg build complete"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

