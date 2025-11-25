#!/usr/bin/env bash
#
# Build FFmpeg for iOS (device + simulator)
#
# This script orchestrates the full build process:
# 1. Downloads sources if needed
# 2. Applies patches for iOS library usage
# 3. Builds LAME (libmp3lame)
# 4. Builds FFmpeg
# 5. Creates XCFramework
#
# Usage: ./build-ffmpeg-ios.sh [options]
#
# Options:
#   --clean         Clean all build artifacts before building
#   --lame-only     Only build LAME
#   --ffmpeg-only   Only build FFmpeg (assumes LAME is already built)
#   --xcf-only      Only create XCFramework (assumes FFmpeg is already built)
#   --no-clean      Skip initial clean (for incremental builds)
#   --version VER   FFmpeg version to build (e.g., "7.0", "git", or "latest")
#   --help          Show this help message
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Initialize build report
init_report

# Parse command line arguments
CLEAN_BUILD=true
BUILD_LAME=true
BUILD_FFMPEG=true
CREATE_XCF=true
FFMPEG_VERSION=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --clean)
      CLEAN_BUILD=true
      shift
      ;;
    --no-clean)
      CLEAN_BUILD=false
      shift
      ;;
    --lame-only)
      BUILD_LAME=true
      BUILD_FFMPEG=false
      CREATE_XCF=false
      shift
      ;;
    --ffmpeg-only)
      BUILD_LAME=false
      BUILD_FFMPEG=true
      CREATE_XCF=false
      CLEAN_BUILD=false
      shift
      ;;
    --xcf-only)
      BUILD_LAME=false
      BUILD_FFMPEG=false
      CREATE_XCF=true
      CLEAN_BUILD=false
      shift
      ;;
    --version)
      FFMPEG_VERSION="$2"
      export FFMPEG_VERSION
      shift 2
      ;;
    --help|-h)
      head -25 "$0" | tail -17
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Clean previous builds
if [ "$CLEAN_BUILD" = true ]; then
  log_section "Cleaning previous builds"
  rm -rf "$BUILD_DIR" "$INSTALL_DIR" "$UMBRELLA_DIR" "$XCFRAMEWORK_PATH"
  mkdir -p "$BUILD_DIR" "$INSTALL_DIR" "$UMBRELLA_DIR"
fi

# Ensure directories exist
mkdir -p "$BUILD_DIR" "$INSTALL_DIR" "$UMBRELLA_DIR"

# Build LAME
if [ "$BUILD_LAME" = true ]; then
  "$SCRIPT_DIR/build/build-lame.sh"
fi

# Build FFmpeg
if [ "$BUILD_FFMPEG" = true ]; then
  "$SCRIPT_DIR/build/build-ffmpeg.sh"
fi

# Create XCFramework
if [ "$CREATE_XCF" = true ]; then
  "$SCRIPT_DIR/build/create-xcframework.sh"
fi

log_section "Build Complete"
log "FFmpeg.xcframework is at: $XCFRAMEWORK_PATH"

# Finalize report
finalize_report
