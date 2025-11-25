#!/usr/bin/env bash
# Apply patches to FFmpeg source for iOS library usage
set -e

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BUILD_SCRIPT_DIR/../config.sh"

log_section "Applying patches to FFmpeg source"

FFMPEG_C="$FFMPEG_SRC_DIR/fftools/ffmpeg.c"
FFMPEG_H="$FFMPEG_SRC_DIR/fftools/ffmpeg.h"
OPT_COMMON_C="$FFMPEG_SRC_DIR/fftools/opt_common.c"

# Track if we need to apply any patches
NEED_FFMPEG_PATCH=true
NEED_OPT_COMMON_PATCH=true

# Check if ffmpeg.c patch is already applied
if grep -q "ffmpeg_reset" "$FFMPEG_C" 2>/dev/null; then
  log "ffmpeg.c patch already applied"
  NEED_FFMPEG_PATCH=false
fi

# Check if opt_common.c patch is already applied
if grep -q "library_program_name" "$OPT_COMMON_C" 2>/dev/null; then
  log "opt_common.c patch already applied"
  NEED_OPT_COMMON_PATCH=false
fi

# Exit if all patches are already applied
if [ "$NEED_FFMPEG_PATCH" = false ] && [ "$NEED_OPT_COMMON_PATCH" = false ]; then
  log "All patches already applied, skipping..."
  exit 0
fi

# Backup original files if needed
if [ "$NEED_FFMPEG_PATCH" = true ]; then
  log "Backing up ffmpeg files..."
  cp "$FFMPEG_C" "$FFMPEG_C.orig"
  cp "$FFMPEG_H" "$FFMPEG_H.orig"
fi

# ============================================================================
# Patch ffmpeg.c - Add ffmpeg_reset() function for re-entrant calls
# ============================================================================

if [ "$NEED_FFMPEG_PATCH" = true ]; then
  log "Patching ffmpeg.c..."

  # Find the line with "static int64_t copy_ts_first_pts = AV_NOPTS_VALUE;"
  # and insert the reset function after it

  PATCH_MARKER="static int64_t copy_ts_first_pts = AV_NOPTS_VALUE;"

  # Create a temporary file with the reset function
  RESET_FUNC_FILE=$(mktemp)
  cat > "$RESET_FUNC_FILE" << 'RESET_FUNC_EOF'

// Reset all global state for re-entrant calls (iOS library usage)
void ffmpeg_reset(void)
{
    // Reset static variables
    received_sigterm = 0;
    received_nb_signals = 0;
    atomic_store(&transcode_init_done, 0);
    ffmpeg_exited = 0;
    copy_ts_first_pts = AV_NOPTS_VALUE;
    
    // Reset atomic counter
    atomic_store(&nb_output_dumped, 0);
    
    // Reset global counters (arrays are freed by ffmpeg_cleanup, just reset counts)
    nb_input_files = 0;
    nb_output_files = 0;
    nb_filtergraphs = 0;
    nb_decoders = 0;
    
    // Ensure pointers are NULL (should already be NULL after cleanup)
    input_files = NULL;
    output_files = NULL;
    filtergraphs = NULL;
    decoders = NULL;
    
    // Reset other globals that may persist
    vstats_file = NULL;
    progress_avio = NULL;
}
RESET_FUNC_EOF

  # Use sed to insert the function after the marker line
  # On macOS, sed -i requires a backup extension (use '' for no backup)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "/$PATCH_MARKER/r $RESET_FUNC_FILE" "$FFMPEG_C"
  else
    sed -i "/$PATCH_MARKER/r $RESET_FUNC_FILE" "$FFMPEG_C"
  fi

  rm "$RESET_FUNC_FILE"

  # Verify patch was applied
  if ! grep -q "ffmpeg_reset" "$FFMPEG_C"; then
    log "ERROR: Failed to patch ffmpeg.c"
    mv "$FFMPEG_C.orig" "$FFMPEG_C"
    exit 1
  fi

  log "Successfully patched ffmpeg.c"

  # ============================================================================
  # Patch ffmpeg.h - Add ffmpeg_reset() declaration
  # ============================================================================

  log "Patching ffmpeg.h..."

  # Find "void term_exit(void);" and add declaration after it
  HEADER_MARKER="void term_exit(void);"

  # Create a temporary file with the header declaration
  HEADER_DECL_FILE=$(mktemp)
  cat > "$HEADER_DECL_FILE" << 'HEADER_DECL_EOF'

// Reset all global state for re-entrant calls (iOS library usage)
void ffmpeg_reset(void);
HEADER_DECL_EOF

  # Use sed to insert the declaration after the marker line
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "/$HEADER_MARKER/r $HEADER_DECL_FILE" "$FFMPEG_H"
  else
    sed -i "/$HEADER_MARKER/r $HEADER_DECL_FILE" "$FFMPEG_H"
  fi

  rm "$HEADER_DECL_FILE"

  # Verify patch was applied
  if ! grep -q "ffmpeg_reset" "$FFMPEG_H"; then
    log "ERROR: Failed to patch ffmpeg.h"
    mv "$FFMPEG_H.orig" "$FFMPEG_H"
    exit 1
  fi

  log "Successfully patched ffmpeg.h"
fi

# ============================================================================
# Patch opt_common.c - Add settable program name for library mode
# ============================================================================

if [ "$NEED_OPT_COMMON_PATCH" = true ] && [ -f "$OPT_COMMON_C" ]; then
  log "Patching opt_common.c..."
  
  cp "$OPT_COMMON_C" "$OPT_COMMON_C.orig"
  
  # Add the library_program_name variable and setter function after the includes
  INCLUDE_MARKER='#include "opt_common.h"'
  
  LIBRARY_NAME_FILE=$(mktemp)
  cat > "$LIBRARY_NAME_FILE" << 'LIBRARY_NAME_EOF'

// Library mode: settable program name for iOS library usage
static const char *library_program_name = NULL;

// Prototype declaration for set_library_program_name
void set_library_program_name(const char *name);

void set_library_program_name(const char *name) {
    library_program_name = name;
}

// Helper to get effective program name
static const char *get_effective_program_name(void) {
    if (library_program_name != NULL) {
        return library_program_name;
    }
    return program_name;
}
LIBRARY_NAME_EOF

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "/$INCLUDE_MARKER/r $LIBRARY_NAME_FILE" "$OPT_COMMON_C"
  else
    sed -i "/$INCLUDE_MARKER/r $LIBRARY_NAME_FILE" "$OPT_COMMON_C"
  fi
  
  rm "$LIBRARY_NAME_FILE"
  
  # Replace program_name with get_effective_program_name() in print_program_info
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's/"%s version " FFMPEG_VERSION, program_name/"%s version " FFMPEG_VERSION, get_effective_program_name()/g' "$OPT_COMMON_C"
  else
    sed -i 's/"%s version " FFMPEG_VERSION, program_name/"%s version " FFMPEG_VERSION, get_effective_program_name()/g' "$OPT_COMMON_C"
  fi
  
  # Verify patch was applied
  if grep -q "library_program_name" "$OPT_COMMON_C"; then
    log "Successfully patched opt_common.c"
  else
    log "Warning: Failed to patch opt_common.c"
    mv "$OPT_COMMON_C.orig" "$OPT_COMMON_C"
  fi
else
  log "opt_common.c already patched or not found, skipping..."
fi

# Clean up backup files (optional - keep them for reference)
# rm "$FFMPEG_C.orig" "$FFMPEG_H.orig"

log_section "All patches applied successfully"
