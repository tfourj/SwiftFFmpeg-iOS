#!/usr/bin/env bash
# Shared configuration for FFmpeg iOS build scripts

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source directories
FFMPEG_SRC_DIR="$PROJECT_ROOT/ffmpeg"
LAME_SRC_DIR="$PROJECT_ROOT/lame"
LIBVPX_VERSION="1.15.2"
OPUS_VERSION="1.5.2"
LIBVPX_SRC_DIR="$PROJECT_ROOT/libvpx-$LIBVPX_VERSION"
OPUS_SRC_DIR="$PROJECT_ROOT/opus-$OPUS_VERSION"

# Build directories
BUILD_DIR="$PROJECT_ROOT/build"
INSTALL_DIR="$PROJECT_ROOT/install"
UMBRELLA_DIR="$PROJECT_ROOT/umbrella"
XCFRAMEWORK_PATH="$PROJECT_ROOT/FFmpeg.xcframework"

# Patches directory
PATCHES_DIR="$SCRIPT_DIR/patches"

# Build settings
MIN_IOS_VERSION="13.0"
NUM_JOBS="$(
  sysctl -n hw.ncpu 2>/dev/null ||
  getconf _NPROCESSORS_ONLN 2>/dev/null ||
  echo 4
)"

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
  --enable-libvpx
  --enable-libopus
  --enable-gpl
  --enable-pthreads
)

# Download pinned codec sources into a temporary directory and verify them before
# exposing the source tree to subsequent builds.
download_codec_source() (
  set -euo pipefail
  local name="$1" url="$2" checksum="$3" source_dir="$4"
  if [ -d "$source_dir" ]; then
    log "$name source already present: $source_dir"
    return
  fi
  mkdir -p "$BUILD_DIR"
  local download_dir
  download_dir=$(mktemp -d "$BUILD_DIR/codec-source.XXXXXX")
  trap 'rm -rf "$download_dir"' EXIT
  log_section "Downloading $name source"
  curl --fail --location --retry 3 "$url" -o "$download_dir/source.tar.gz"
  printf '%s  %s\n' "$checksum" "$download_dir/source.tar.gz" | shasum -a 256 --check
  mkdir "$download_dir/source"
  tar -xzf "$download_dir/source.tar.gz" -C "$download_dir/source" --strip-components=1
  mv "$download_dir/source" "$source_dir"
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
