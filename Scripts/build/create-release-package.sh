#!/usr/bin/env bash
set -euo pipefail

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

RELEASE_TAG=""
REPOSITORY_SLUG=""
OUTPUT_DIR="$PROJECT_ROOT/release"
ASSET_NAME="FFmpeg.xcframework.zip"
METADATA_PATH="$PROJECT_ROOT/Package.release.json"

usage() {
  cat <<EOF
Usage: ./Scripts/build/create-release-package.sh --tag <tag> --repo <owner/repo> [--output-dir <dir>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      RELEASE_TAG="$2"
      shift 2
      ;;
    --repo)
      REPOSITORY_SLUG="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
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

if [[ -z "$RELEASE_TAG" || -z "$REPOSITORY_SLUG" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$XCFRAMEWORK_PATH" ]]; then
  echo "FFmpeg.xcframework not found at $XCFRAMEWORK_PATH" >&2
  echo "Run ./Scripts/build-ffmpeg-ios.sh first." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
ASSET_PATH="$OUTPUT_DIR/$ASSET_NAME"
rm -f "$ASSET_PATH"

log_section "Packaging release artifact"
ditto -c -k --sequesterRsrc --keepParent "$XCFRAMEWORK_PATH" "$ASSET_PATH"

CHECKSUM="$(swift package compute-checksum "$ASSET_PATH")"
ASSET_URL="https://github.com/$REPOSITORY_SLUG/releases/download/$RELEASE_TAG/$ASSET_NAME"

cat > "$METADATA_PATH" <<EOF
{
  "version": "$RELEASE_TAG",
  "url": "$ASSET_URL",
  "checksum": "$CHECKSUM"
}
EOF

log "Release archive created at: $ASSET_PATH"
log "Package metadata updated at: $METADATA_PATH"
log "Checksum: $CHECKSUM"
