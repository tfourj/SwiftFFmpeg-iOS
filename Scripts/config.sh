#!/usr/bin/env bash
# Shared configuration for FFmpeg iOS build scripts

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source directories
FFMPEG_SRC_DIR="$PROJECT_ROOT/ffmpeg"
LAME_SRC_DIR="$PROJECT_ROOT/lame"

# Build directories
BUILD_DIR="$PROJECT_ROOT/build"
INSTALL_DIR="$PROJECT_ROOT/install"
UMBRELLA_DIR="$PROJECT_ROOT/umbrella"
XCFRAMEWORK_PATH="$PROJECT_ROOT/FFmpeg.xcframework"

# Patches directory
PATCHES_DIR="$SCRIPT_DIR/patches"

# Build settings
MIN_IOS_VERSION="13.0"
NUM_JOBS="$(sysctl -n hw.ncpu)"

# Common FFmpeg configure flags
COMMON_FFMPEG_FLAGS=(
  --disable-shared
  --enable-static
  --disable-doc
  --disable-debug
  --enable-pic
  --enable-libmp3lame
  --enable-gpl
  --enable-pthreads
)

# Helper function to get platform suffix
get_platform_suffix() {
  local PLATFORM=$1
  if [ "$PLATFORM" = "iphonesimulator" ]; then
    echo "sim"
  else
    echo "ios"
  fi
}

# Helper function to get target triple
get_target_triple() {
  local ARCH=$1
  local PLATFORM=$2
  if [ "$PLATFORM" = "iphonesimulator" ]; then
    echo "${ARCH}-apple-ios${MIN_IOS_VERSION}-simulator"
  else
    echo "${ARCH}-apple-ios${MIN_IOS_VERSION}"
  fi
}

# Helper function to log with timestamp
log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

# Helper function to log section headers
log_section() {
  echo ""
  echo "==== $* ===="
  echo ""
}

