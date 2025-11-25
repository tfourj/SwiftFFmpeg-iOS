#!/usr/bin/env bash
# Build FFmpeg for iOS
set -e

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

# Get available FFmpeg stable versions from GitHub
get_ffmpeg_versions() {
  # Fetch tags from GitHub API (last 20 releases)
  # Suppress all output except version numbers
  VERSIONS=$(curl -s "https://api.github.com/repos/FFmpeg/FFmpeg/tags?per_page=20" 2>/dev/null | \
    grep -o '"name": "n[0-9.]*"' 2>/dev/null | \
    sed 's/"name": "n\(.*\)"/\1/' 2>/dev/null | \
    sort -V -r 2>/dev/null | \
    head -10 2>/dev/null)
  
  if [ -z "$VERSIONS" ]; then
    # Fallback: use known stable versions
    echo "8.0.1 8.0 7.1.3 7.1.2 7.1.1 7.1 7.0.3 7.0.2 7.0.1 7.0"
  else
    echo "$VERSIONS"
  fi
}

# Prompt user to select FFmpeg version
select_ffmpeg_version() {
  local SELECTED_VERSION=""
  
  # Check if version is provided via environment variable
  if [ -n "$FFMPEG_VERSION" ]; then
    if [ "$FFMPEG_VERSION" = "latest" ] || [ "$FFMPEG_VERSION" = "git" ]; then
      echo "git"
      return
    else
      echo "$FFMPEG_VERSION"
      return
    fi
  fi
  
  # Check if running non-interactively (no TTY)
  if [ ! -t 0 ]; then
    log "Non-interactive mode detected, using latest git"
    echo "git"
    return
  fi
  
  # Interactive prompt (send prompts to stderr so stdout only contains version)
  echo "" >&2
  echo "Select FFmpeg version to build:" >&2
  echo "  1) Latest Git (recommended for latest features)" >&2
  echo "  2) Stable version (choose from list)" >&2
  echo "" >&2
  printf "Enter choice [1-2] (default: 1): " >&2
  read choice < /dev/tty 2>/dev/null || read choice
  choice=${choice:-1}
  
  if [ "$choice" = "1" ]; then
    echo "git"
    return
  fi
  
  if [ "$choice" = "2" ]; then
    # Get versions (suppress any log output)
    local versions=($(get_ffmpeg_versions 2>/dev/null))
    local version_input=""
    
    if [ ${#versions[@]} -eq 0 ]; then
      log "Failed to fetch versions, using fallback list"
      versions=(8.0.1 8.0 7.1.3 7.1.2 7.1.1 7.1 7.0.3 7.0.2 7.0.1 7.0)
    fi
    
    echo "" >&2
    echo "Available stable versions:" >&2
    local i=1
    for version in "${versions[@]}"; do
      echo "  $i) $version" >&2
      ((i++))
    done
    echo "" >&2
    printf "Enter version number or version string (e.g., 7.0): " >&2
    read version_input < /dev/tty 2>/dev/null || read version_input
    
    # Check if it's a number (index) or version string
    if [[ "$version_input" =~ ^[0-9]+$ ]]; then
      local idx=$((version_input - 1))
      if [ $idx -ge 0 ] && [ $idx -lt ${#versions[@]} ]; then
        SELECTED_VERSION="${versions[$idx]}"
      else
        log "Invalid selection, using latest git"
        echo "git"
        return
      fi
    else
      SELECTED_VERSION="$version_input"
    fi
    
    echo "$SELECTED_VERSION"
  else
    log "Invalid choice, using latest git"
    echo "git"
  fi
}

# Download FFmpeg if not present
download_ffmpeg() {
  if [ -f "$FFMPEG_SRC_DIR/configure" ]; then
    log "FFmpeg source already present"
    return 0
  fi
  
  log_section "Downloading FFmpeg source"
  cd "$PROJECT_ROOT"
  
  # Select version
  local VERSION=$(select_ffmpeg_version)
  
  if [ "$VERSION" = "git" ]; then
    log "Downloading latest FFmpeg from git..."
    if command -v git &> /dev/null; then
      git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git ffmpeg || {
        log "Failed to clone FFmpeg. Trying GitHub..."
        git clone --depth 1 https://github.com/FFmpeg/FFmpeg.git ffmpeg || {
          log "Error: Failed to clone FFmpeg"
          exit 1
        }
      }
    else
      log "Error: git is not installed"
      exit 1
    fi
  else
    log "Downloading FFmpeg version $VERSION..."
    # Download specific version from GitHub
    curl -L "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${VERSION}.tar.gz" -o ffmpeg.tar.gz || {
      log "Error: Failed to download FFmpeg version $VERSION"
      exit 1
    }
    tar -xzf ffmpeg.tar.gz
    mv "FFmpeg-n${VERSION}" ffmpeg
    rm ffmpeg.tar.gz
  fi
  
  if [ ! -f "$FFMPEG_SRC_DIR/configure" ]; then
    log "Error: Failed to obtain FFmpeg source"
    exit 1
  fi
  
  log "FFmpeg source downloaded successfully"
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
  
  # Recompile opt_common.c with our patched version that supports settable program_name
  if [ -f "$FFMPEG_SRC_DIR/fftools/opt_common.c" ]; then
    log "Recompiling opt_common.c with program name patch..."
    $COMPILER "${COMMON_COMPILE_FLAGS[@]}" \
      -c "$FFMPEG_SRC_DIR/fftools/opt_common.c" -o "$TEMP_DIR/opt_common.o"
    
    if [ ! -f "$TEMP_DIR/opt_common.o" ]; then
      log "Warning: Failed to compile opt_common.c"
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

