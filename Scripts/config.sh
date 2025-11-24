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

# Report file for clean build summary
REPORT_FILE="$PROJECT_ROOT/build-report.txt"

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

# Initialize report file
init_report() {
  local BUILD_START=$(date '+%Y-%m-%d %H:%M:%S')
  cat > "$REPORT_FILE" << EOF
================================================================================
FFmpeg iOS Build Report
================================================================================
Build started: $BUILD_START
Project: SwiftFFmpeg-iOS
================================================================================

EOF
}

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

# Helper function to log with timestamp (writes to both stdout and report)
log() {
  local MSG="[$(date '+%H:%M:%S')] $*"
  echo "$MSG"
  echo "$MSG" >> "$REPORT_FILE"
}

# Helper function to log section headers (writes to both stdout and report)
log_section() {
  local SECTION="==== $* ===="
  echo ""
  echo "$SECTION"
  echo ""
  echo "" >> "$REPORT_FILE"
  echo "$SECTION" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
}

# Helper function to log to report only (not stdout)
log_report() {
  echo "[$(date '+%H:%M:%S')] $*" >> "$REPORT_FILE"
}

# Helper function to run a command and log its status to report
# Usage: run_with_report "description" command [args...]
run_with_report() {
  local DESC="$1"
  shift
  log_report "Starting: $DESC"
  if "$@" >> "$REPORT_FILE" 2>&1; then
    log_report "✓ Completed: $DESC"
    return 0
  else
    local EXIT_CODE=$?
    log_report "✗ Failed: $DESC (exit code: $EXIT_CODE)"
    return $EXIT_CODE
  fi
}

# Helper function to run make commands - shows output on stdout, logs summary to report
# Usage: make_with_report [make args...]
make_with_report() {
  local CMD="make $*"
  log_report "Running: $CMD"
  
  # Run make normally (output goes to stdout for real-time feedback)
  # But capture exit code
  if make "$@"; then
    log_report "✓ Completed: $CMD"
    return 0
  else
    local EXIT_CODE=$?
    log_report "✗ Failed: $CMD (exit code: $EXIT_CODE)"
    return $EXIT_CODE
  fi
}

# Finalize report file
finalize_report() {
  local BUILD_END=$(date '+%Y-%m-%d %H:%M:%S')
  cat >> "$REPORT_FILE" << EOF

================================================================================
Build completed: $BUILD_END
Report saved to: $REPORT_FILE
================================================================================
EOF
  log "Build report saved to: $REPORT_FILE"
}

