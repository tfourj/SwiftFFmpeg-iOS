#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Execute FFmpeg as if calling its CLI.
/// \param argc Number of arguments
/// \param argv Array of C strings (argv[0] is normally "ffmpeg")
/// \return FFmpeg exit code (0 = success)
int ffmpeg_execute(int argc, char *argv[]);

/// Swift-side log callback type:
/// level is FFmpeg log level (e.g. AV_LOG_INFO, AV_LOG_ERROR, etc.)
typedef void (*ffmpeg_swift_log_func)(int level, const char *message);

/// Register a Swift log callback. Pass NULL to disable forwarding.
void ffmpeg_set_swift_logger(ffmpeg_swift_log_func func);

/// Set FFmpeg log level (e.g. 32 = info, 16 = warning, 8 = error, etc.)
void ffmpeg_set_log_level(int level);

/// Request cancellation of the active FFmpeg/ffprobe execution, if any.
void ffmpeg_request_cancel(void);

/// Clear any pending FFmpeg/ffprobe cancellation request.
void ffmpeg_clear_cancel(void);

/// Execute ffprobe as if calling its CLI.
/// \param argc Number of arguments
/// \param argv Array of C strings (argv[0] is normally "ffprobe")
/// \return ffprobe exit code (0 = success)
int ffprobe_execute(int argc, char *argv[]);

/// Execute FFmpeg and capture stdout/stderr output separately.
/// \param argc Number of arguments
/// \param argv Array of C strings (argv[0] is normally "ffmpeg")
/// \param stdout_buffer Buffer to store stdout (will be null-terminated)
/// \param stdout_buffer_size Size of stdout_buffer
/// \param stderr_buffer Buffer to store stderr (will be null-terminated)
/// \param stderr_buffer_size Size of stderr_buffer
/// \return FFmpeg exit code (0 = success)
int ffmpeg_execute_with_output(
    int argc,
    char *argv[],
    char *stdout_buffer,
    size_t stdout_buffer_size,
    char *stderr_buffer,
    size_t stderr_buffer_size
);

/// Execute ffprobe and capture stdout/stderr output separately.
/// \param argc Number of arguments
/// \param argv Array of C strings (argv[0] is normally "ffprobe")
/// \param stdout_buffer Buffer to store stdout (will be null-terminated)
/// \param stdout_buffer_size Size of stdout_buffer
/// \param stderr_buffer Buffer to store stderr (will be null-terminated)
/// \param stderr_buffer_size Size of stderr_buffer
/// \return ffprobe exit code (0 = success)
int ffprobe_execute_with_output(
    int argc,
    char *argv[],
    char *stdout_buffer,
    size_t stdout_buffer_size,
    char *stderr_buffer,
    size_t stderr_buffer_size
);

#ifdef __cplusplus
}
#endif
