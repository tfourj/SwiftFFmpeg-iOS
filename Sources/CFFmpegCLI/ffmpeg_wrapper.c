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

// Set program name for library mode (from patched opt_common.c)
void set_library_program_name(const char *name);

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
    set_library_program_name("ffmpeg");
    return ffmpeg_main(argc, argv);
}

int ffprobe_execute(int argc, char *argv[]) {
    ffmpeg_setup_logging_if_needed();
    ffmpeg_reset();  // Reset global state before each execution
    set_library_program_name("ffprobe");
    return ffprobe_main(argc, argv);
}

// --- Execute with output capture ---

int ffmpeg_execute_with_output(int argc, char *argv[], char *output_buffer, size_t output_buffer_size) {
    if (!output_buffer || output_buffer_size == 0) {
        return ffmpeg_execute(argc, argv);
    }
    
    // Initialize output buffer
    output_buffer[0] = '\0';
    
    // Create a pipe to capture output
    int pipefd[2];
    if (pipe(pipefd) < 0) {
        return ffmpeg_execute(argc, argv);
    }
    
    // Save original stdout/stderr
    int stdout_fd = dup(STDOUT_FILENO);
    int stderr_fd = dup(STDERR_FILENO);
    
    // Redirect stdout and stderr to pipe write end
    dup2(pipefd[1], STDOUT_FILENO);
    dup2(pipefd[1], STDERR_FILENO);
    close(pipefd[1]);  // Close write end in parent after dup
    
    // Execute FFmpeg
    ffmpeg_setup_logging_if_needed();
    ffmpeg_reset();  // Reset global state before each execution
    set_library_program_name("ffmpeg");
    int exit_code = ffmpeg_main(argc, argv);
    
    // Restore stdout/stderr
    fflush(stdout);
    fflush(stderr);
    dup2(stdout_fd, STDOUT_FILENO);
    dup2(stderr_fd, STDERR_FILENO);
    close(stdout_fd);
    close(stderr_fd);
    
    // Read output from pipe
    size_t total_read = 0;
    ssize_t bytes_read;
    while (total_read < output_buffer_size - 1) {
        bytes_read = read(pipefd[0], output_buffer + total_read, output_buffer_size - 1 - total_read);
        if (bytes_read <= 0) break;
        total_read += bytes_read;
    }
    output_buffer[total_read] = '\0';
    
    // Close read end of pipe
    close(pipefd[0]);
    
    return exit_code;
}

// --- Execute ffprobe with output capture ---

int ffprobe_execute_with_output(int argc, char *argv[], char *output_buffer, size_t output_buffer_size) {
    if (!output_buffer || output_buffer_size == 0) {
        return ffprobe_execute(argc, argv);
    }
    
    // Initialize output buffer
    output_buffer[0] = '\0';
    
    // Create a pipe to capture output
    int pipefd[2];
    if (pipe(pipefd) < 0) {
        return ffprobe_execute(argc, argv);
    }
    
    // Save original stdout/stderr
    int stdout_fd = dup(STDOUT_FILENO);
    int stderr_fd = dup(STDERR_FILENO);
    
    // Redirect stdout and stderr to pipe write end
    dup2(pipefd[1], STDOUT_FILENO);
    dup2(pipefd[1], STDERR_FILENO);
    close(pipefd[1]);  // Close write end in parent after dup
    
    // Execute ffprobe
    ffmpeg_setup_logging_if_needed();
    ffmpeg_reset();  // Reset global state before each execution
    set_library_program_name("ffprobe");
    int exit_code = ffprobe_main(argc, argv);
    
    // Restore stdout/stderr
    fflush(stdout);
    fflush(stderr);
    dup2(stdout_fd, STDOUT_FILENO);
    dup2(stderr_fd, STDERR_FILENO);
    close(stdout_fd);
    close(stderr_fd);
    
    // Read output from pipe
    size_t total_read = 0;
    ssize_t bytes_read;
    while (total_read < output_buffer_size - 1) {
        bytes_read = read(pipefd[0], output_buffer + total_read, output_buffer_size - 1 - total_read);
        if (bytes_read <= 0) break;
        total_read += bytes_read;
    }
    output_buffer[total_read] = '\0';
    
    // Close read end of pipe
    close(pipefd[0]);
    
    return exit_code;
}
