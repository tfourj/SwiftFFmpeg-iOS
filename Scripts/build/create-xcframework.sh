#!/usr/bin/env bash
# Create XCFramework from built FFmpeg libraries
set -e

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

# Helper function to create thin umbrella library
create_umbrella_lib() {
  local OUTPUT="$1"
  local ARCH="$2"
  shift 2
  local LIBS=("$@")
  
  log "Creating umbrella library: $(basename "$OUTPUT")"
  
  # Create temporary directory for thin libraries
  local TEMP_DIR=$(mktemp -d)
  
  # Extract thin slices and combine
  local THIN_LIBS=()
  for lib in "${LIBS[@]}"; do
    local THIN_LIB="$TEMP_DIR/$(basename "$lib")"
    # Extract thin slice for the architecture (if universal, otherwise copy as-is)
    if lipo -info "$lib" 2>/dev/null | grep -q "architectures:"; then
      lipo "$lib" -thin "$ARCH" -output "$THIN_LIB"
    else
      cp "$lib" "$THIN_LIB"
    fi
    THIN_LIBS+=("$THIN_LIB")
  done
  
  # Combine into single library
  libtool -static -o "$OUTPUT.tmp" "${THIN_LIBS[@]}"
  
  # Ensure output is thin (single architecture)
  if lipo -info "$OUTPUT.tmp" 2>/dev/null | grep -q "architectures:"; then
    lipo "$OUTPUT.tmp" -thin "$ARCH" -output "$OUTPUT"
    rm "$OUTPUT.tmp"
  else
    mv "$OUTPUT.tmp" "$OUTPUT"
  fi
  
  rm -rf "$TEMP_DIR"
}

# Create umbrella libraries
create_umbrella_libs() {
  log_section "Creating umbrella static libraries"

  mkdir -p "$UMBRELLA_DIR/ios-arm64" "$UMBRELLA_DIR/iossim-arm64"

  # iOS device arm64
  create_umbrella_lib "$UMBRELLA_DIR/ios-arm64/libFFmpeg.a" arm64 \
    "$INSTALL_DIR/arm64-ios/lib/libavcodec.a" \
    "$INSTALL_DIR/arm64-ios/lib/libavformat.a" \
    "$INSTALL_DIR/arm64-ios/lib/libavutil.a" \
    "$INSTALL_DIR/arm64-ios/lib/libavfilter.a" \
    "$INSTALL_DIR/arm64-ios/lib/libavdevice.a" \
    "$INSTALL_DIR/arm64-ios/lib/libswresample.a" \
    "$INSTALL_DIR/arm64-ios/lib/libswscale.a" \
    "$INSTALL_DIR/arm64-ios/lib/libmp3lame.a" \
    "$INSTALL_DIR/arm64-ios/lib/libffmpeg_cli.a"

  # iOS simulator arm64
  create_umbrella_lib "$UMBRELLA_DIR/iossim-arm64/libFFmpeg.a" arm64 \
    "$INSTALL_DIR/arm64-sim/lib/libavcodec.a" \
    "$INSTALL_DIR/arm64-sim/lib/libavformat.a" \
    "$INSTALL_DIR/arm64-sim/lib/libavutil.a" \
    "$INSTALL_DIR/arm64-sim/lib/libavfilter.a" \
    "$INSTALL_DIR/arm64-sim/lib/libavdevice.a" \
    "$INSTALL_DIR/arm64-sim/lib/libswresample.a" \
    "$INSTALL_DIR/arm64-sim/lib/libswscale.a" \
    "$INSTALL_DIR/arm64-sim/lib/libmp3lame.a" \
    "$INSTALL_DIR/arm64-sim/lib/libffmpeg_cli.a"

  log "Umbrella libraries created"
}

# Create XCFramework
create_xcframework() {
  log_section "Creating FFmpeg.xcframework"

  cd "$PROJECT_ROOT"

  # Remove existing xcframework
  rm -rf "$XCFRAMEWORK_PATH"

  xcodebuild -create-xcframework \
    -library "$UMBRELLA_DIR/ios-arm64/libFFmpeg.a" -headers "$INSTALL_DIR/arm64-ios/include" \
    -library "$UMBRELLA_DIR/iossim-arm64/libFFmpeg.a" -headers "$INSTALL_DIR/arm64-sim/include" \
    -output "$XCFRAMEWORK_PATH"

  log "XCFramework created at: $XCFRAMEWORK_PATH"
}

# Main execution
main() {
  create_umbrella_libs
  create_xcframework
  
  log_section "XCFramework creation complete"
  log "Done! FFmpeg.xcframework is at: $XCFRAMEWORK_PATH"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

