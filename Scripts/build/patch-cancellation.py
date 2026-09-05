#!/usr/bin/env python3
"""Connect FFmpeg's scheduler and I/O cancellation to the library wrapper."""

from pathlib import Path
import sys

path = Path(sys.argv[1]) / "fftools" / "ffmpeg.c"
source = path.read_text()
old_declaration = (
    "// The embedding wrapper owns this atomic cancellation state.\n"
    "extern int ffmpeg_library_cancel_requested(void);"
)
declaration = (
    "// Only the embedded CLI links against the application's wrapper.\n"
    "#ifdef FFMPEG_LIBRARY_MODE\n"
    "extern int ffmpeg_library_cancel_requested(void);\n"
    "#else\n"
    "static int ffmpeg_library_cancel_requested(void) { return 0; }\n"
    "#endif"
)

# Upgrade source trees patched by the previous version as well as fresh sources.
if old_declaration in source:
    source = source.replace(old_declaration, declaration)

replacements = {
    "static volatile int received_sigterm = 0;":
        declaration + "\n\n"
        "static volatile int received_sigterm = 0;",
    "return received_nb_signals > atomic_load(&transcode_init_done);":
        "return ffmpeg_library_cancel_requested() ||\n"
        "           received_nb_signals > atomic_load(&transcode_init_done);",
    "while (!sch_wait(sch, stats_period, &transcode_ts)) {":
        "while (!ffmpeg_library_cancel_requested() &&\n"
        "           !sch_wait(sch, FFMIN(stats_period, 20000), &transcode_ts)) {",
    "    if (ret == AVERROR_EXIT)\n        ret = 0;":
        "    if (ffmpeg_library_cancel_requested())\n"
        "        ret = 255;\n"
        "    else if (ret == AVERROR_EXIT)\n        ret = 0;",
}

for old, new in replacements.items():
    if new in source:
        continue
    if source.count(old) != 1:
        raise SystemExit(f"Unsupported FFmpeg cancellation patch location: {old}")
    source = source.replace(old, new)

path.write_text(source)
