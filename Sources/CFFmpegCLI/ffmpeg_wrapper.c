#include "ffmpeg_wrapper.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <pthread.h>

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
static pthread_mutex_t g_exec_mutex = PTHREAD_MUTEX_INITIALIZER;

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

typedef struct {
    int fd;
    char *buffer;
    size_t buffer_size;
    size_t total_read;
} output_reader_ctx;

static void *output_reader_thread(void *arg) {
    output_reader_ctx *ctx = (output_reader_ctx *)arg;
    char temp[4096];

    while (1) {
        ssize_t bytes_read = read(ctx->fd, temp, sizeof(temp));
        if (bytes_read <= 0) {
            break;
        }

        if (ctx->buffer && ctx->buffer_size > 1 && ctx->total_read < (ctx->buffer_size - 1)) {
            size_t remaining = (ctx->buffer_size - 1) - ctx->total_read;
            size_t to_copy = (size_t)bytes_read < remaining ? (size_t)bytes_read : remaining;
            memcpy(ctx->buffer + ctx->total_read, temp, to_copy);
            ctx->total_read += to_copy;
        }
    }

    if (ctx->buffer && ctx->buffer_size > 0) {
        size_t end = ctx->total_read < (ctx->buffer_size - 1) ? ctx->total_read : (ctx->buffer_size - 1);
        ctx->buffer[end] = '\0';
    }

    return NULL;
}

static int execute_with_output_common(
    int argc,
    char *argv[],
    char *output_buffer,
    size_t output_buffer_size,
    int (*tool_main)(int, char *[]),
    const char *program_name
) {
    pthread_mutex_lock(&g_exec_mutex);

    if (!output_buffer || output_buffer_size == 0) {
        ffmpeg_setup_logging_if_needed();
        ffmpeg_reset();
        set_library_program_name(program_name);
        int code = tool_main(argc, argv);
        pthread_mutex_unlock(&g_exec_mutex);
        return code;
    }

    output_buffer[0] = '\0';

    int pipefd[2];
    if (pipe(pipefd) < 0) {
        ffmpeg_setup_logging_if_needed();
        ffmpeg_reset();
        set_library_program_name(program_name);
        int code = tool_main(argc, argv);
        pthread_mutex_unlock(&g_exec_mutex);
        return code;
    }

    int stdout_fd = dup(STDOUT_FILENO);
    int stderr_fd = dup(STDERR_FILENO);
    if (stdout_fd < 0 || stderr_fd < 0) {
        if (stdout_fd >= 0) close(stdout_fd);
        if (stderr_fd >= 0) close(stderr_fd);
        close(pipefd[0]);
        close(pipefd[1]);
        ffmpeg_setup_logging_if_needed();
        ffmpeg_reset();
        set_library_program_name(program_name);
        int code = tool_main(argc, argv);
        pthread_mutex_unlock(&g_exec_mutex);
        return code;
    }

    if (dup2(pipefd[1], STDOUT_FILENO) < 0 || dup2(pipefd[1], STDERR_FILENO) < 0) {
        dup2(stdout_fd, STDOUT_FILENO);
        dup2(stderr_fd, STDERR_FILENO);
        close(stdout_fd);
        close(stderr_fd);
        close(pipefd[0]);
        close(pipefd[1]);
        ffmpeg_setup_logging_if_needed();
        ffmpeg_reset();
        set_library_program_name(program_name);
        int code = tool_main(argc, argv);
        pthread_mutex_unlock(&g_exec_mutex);
        return code;
    }
    close(pipefd[1]);

    output_reader_ctx reader_ctx = {
        .fd = pipefd[0],
        .buffer = output_buffer,
        .buffer_size = output_buffer_size,
        .total_read = 0
    };
    pthread_t reader_tid;
    int reader_started = (pthread_create(&reader_tid, NULL, output_reader_thread, &reader_ctx) == 0);

    ffmpeg_setup_logging_if_needed();
    ffmpeg_reset();
    set_library_program_name(program_name);
    int exit_code = tool_main(argc, argv);

    fflush(stdout);
    fflush(stderr);
    dup2(stdout_fd, STDOUT_FILENO);
    dup2(stderr_fd, STDERR_FILENO);
    close(stdout_fd);
    close(stderr_fd);

    if (reader_started) {
        pthread_join(reader_tid, NULL);
    } else {
        ssize_t bytes_read;
        size_t total_read = 0;
        while (total_read < output_buffer_size - 1) {
            bytes_read = read(pipefd[0], output_buffer + total_read, output_buffer_size - 1 - total_read);
            if (bytes_read <= 0) break;
            total_read += (size_t)bytes_read;
        }
        output_buffer[total_read] = '\0';
    }

    close(pipefd[0]);
    pthread_mutex_unlock(&g_exec_mutex);
    return exit_code;
}

int ffmpeg_execute_with_output(int argc, char *argv[], char *output_buffer, size_t output_buffer_size) {
    return execute_with_output_common(argc, argv, output_buffer, output_buffer_size, ffmpeg_main, "ffmpeg");
}

// --- Execute ffprobe with output capture ---

int ffprobe_execute_with_output(int argc, char *argv[], char *output_buffer, size_t output_buffer_size) {
    return execute_with_output_common(argc, argv, output_buffer, output_buffer_size, ffprobe_main, "ffprobe");
}
