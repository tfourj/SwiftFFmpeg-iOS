#include "ffmpeg_wrapper.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <fcntl.h>

// --- Forward declarations from FFmpeg (we don't include FFmpeg headers) ---

// from fftools/ffmpeg.c compiled with -Dmain=ffmpeg_main
int ffmpeg_main(int argc, char *argv[]);

// from fftools/ffprobe.c compiled with -Dmain=ffprobe_main
int ffprobe_main(int argc, char *argv[]);

// Reset FFmpeg global state for re-entrant calls
void ffmpeg_reset(void);

// FFmpeg logging API
void av_log_set_callback(void (*callback)(void *ptr, int level, const char *fmt, va_list vl));
void av_log_set_level(int level);

// --- Global state for Swift log callback ---

static ffmpeg_swift_log_func g_swift_log_func = NULL;

// Optional: default log level if Swift doesn't set it
static int g_log_level = 32; // roughly AV_LOG_INFO

void ffmpeg_set_swift_logger(ffmpeg_swift_log_func func) {
    g_swift_log_func = func;
}

void ffmpeg_set_log_level(int level) {
    g_log_level = level;
    av_log_set_level(level);
}

// --- Internal FFmpeg log callback ---

static void ffmpeg_log_callback(void *ptr, int level, const char *fmt, va_list vl) {
    (void)ptr; // unused

    if (!g_swift_log_func) {
        return;
    }

    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), fmt, vl);

    // Ensure null-terminated
    buffer[sizeof(buffer) - 1] = '\0';

    g_swift_log_func(level, buffer);
}

// --- Setup logging once ---

static int g_logging_initialized = 0;

static void ffmpeg_setup_logging_if_needed(void) {
    if (g_logging_initialized) {
        return;
    }
    g_logging_initialized = 1;

    av_log_set_callback(ffmpeg_log_callback);
    av_log_set_level(g_log_level);
}

// --- Main entrypoint used from Swift ---

int ffmpeg_execute(int argc, char *argv[]) {
    ffmpeg_setup_logging_if_needed();
    ffmpeg_reset();  // Reset global state before each execution
    return ffmpeg_main(argc, argv);
}

int ffprobe_execute(int argc, char *argv[]) {
    ffmpeg_setup_logging_if_needed();
    ffmpeg_reset();  // Reset global state before each execution
    return ffprobe_main(argc, argv);
}

// --- Execute with output capture ---

int ffmpeg_execute_with_output(int argc, char *argv[], char *output_buffer, size_t output_buffer_size) {
    if (!output_buffer || output_buffer_size == 0) {
        return ffmpeg_execute(argc, argv);
    }
    
    // Create a temporary file for output
    char temp_file[] = "/tmp/ffmpeg_output_XXXXXX";
    int fd = mkstemp(temp_file);
    if (fd < 0) {
        return ffmpeg_execute(argc, argv);
    }
    
    // Save original stdout/stderr
    int stdout_fd = dup(STDOUT_FILENO);
    int stderr_fd = dup(STDERR_FILENO);
    
    // Redirect stdout and stderr to temp file
    dup2(fd, STDOUT_FILENO);
    dup2(fd, STDERR_FILENO);
    close(fd);
    
    // Execute FFmpeg
    ffmpeg_setup_logging_if_needed();
    ffmpeg_reset();  // Reset global state before each execution
    int exit_code = ffmpeg_main(argc, argv);
    
    // Restore stdout/stderr
    fflush(stdout);
    fflush(stderr);
    dup2(stdout_fd, STDOUT_FILENO);
    dup2(stderr_fd, STDERR_FILENO);
    close(stdout_fd);
    close(stderr_fd);
    
    // Read output from temp file
    FILE *fp = fopen(temp_file, "r");
    if (fp) {
        size_t bytes_read = fread(output_buffer, 1, output_buffer_size - 1, fp);
        output_buffer[bytes_read] = '\0';
        fclose(fp);
    }
    
    // Clean up temp file
    unlink(temp_file);
    
    return exit_code;
}

// --- Execute ffprobe with output capture ---

int ffprobe_execute_with_output(int argc, char *argv[], char *output_buffer, size_t output_buffer_size) {
    if (!output_buffer || output_buffer_size == 0) {
        return ffprobe_execute(argc, argv);
    }
    
    // Create a temporary file for output
    char temp_file[] = "/tmp/ffmpeg_output_XXXXXX";
    int fd = mkstemp(temp_file);
    if (fd < 0) {
        return ffprobe_execute(argc, argv);
    }
    
    // Save original stdout/stderr
    int stdout_fd = dup(STDOUT_FILENO);
    int stderr_fd = dup(STDERR_FILENO);
    
    // Redirect stdout and stderr to temp file
    dup2(fd, STDOUT_FILENO);
    dup2(fd, STDERR_FILENO);
    close(fd);
    
    // Execute FFmpeg
    ffmpeg_setup_logging_if_needed();
    ffmpeg_reset();  // Reset global state before each execution
    int exit_code = ffprobe_main(argc, argv);
    
    // Restore stdout/stderr
    fflush(stdout);
    fflush(stderr);
    dup2(stdout_fd, STDOUT_FILENO);
    dup2(stderr_fd, STDERR_FILENO);
    close(stdout_fd);
    close(stderr_fd);
    
    // Read output from temp file
    FILE *fp = fopen(temp_file, "r");
    if (fp) {
        size_t bytes_read = fread(output_buffer, 1, output_buffer_size - 1, fp);
        output_buffer[bytes_read] = '\0';
        fclose(fp);
    }
    
    // Clean up temp file
    unlink(temp_file);
    
    return exit_code;
}
