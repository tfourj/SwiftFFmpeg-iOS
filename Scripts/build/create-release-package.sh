#!/usr/bin/env bash
set -euo pipefail

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

OUTPUT_DIR="$PROJECT_ROOT/release"
ASSET_NAME="SwiftFFmpeg-iOS.zip"
STAGING_DIR="$OUTPUT_DIR/SwiftFFmpeg-iOS"

usage() {
  cat <<EOF
Usage: ./Scripts/build/create-release-package.sh [--output-dir <dir>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      STAGING_DIR="$OUTPUT_DIR/SwiftFFmpeg-iOS"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$XCFRAMEWORK_PATH" ]]; then
  echo "FFmpeg.xcframework not found at $XCFRAMEWORK_PATH" >&2
  echo "Run ./Scripts/build-ffmpeg-ios.sh first." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
ASSET_PATH="$OUTPUT_DIR/$ASSET_NAME"
rm -rf "$STAGING_DIR"
rm -f "$ASSET_PATH"
mkdir -p "$STAGING_DIR"

log_section "Packaging release artifact"
cp "$PROJECT_ROOT/Package.swift" "$STAGING_DIR/"
cp "$PROJECT_ROOT/LICENSE" "$STAGING_DIR/"
cp "$PROJECT_ROOT/README.md" "$STAGING_DIR/"
cp -R "$PROJECT_ROOT/Sources" "$STAGING_DIR/"
cp -R "$PROJECT_ROOT/Tests" "$STAGING_DIR/"
cp -R "$XCFRAMEWORK_PATH" "$STAGING_DIR/"
find "$STAGING_DIR" -name .DS_Store -delete
ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR" "$ASSET_PATH"

log "Release archive created at: $ASSET_PATH"
log "Package contents staged at: $STAGING_DIR"
