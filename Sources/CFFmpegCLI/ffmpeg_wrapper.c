#include "ffmpeg_wrapper.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>

// --- Forward declarations from FFmpeg (we don't include FFmpeg headers) ---

// from fftools/ffmpeg.c compiled with -Dmain=ffmpeg_main
int ffmpeg_main(int argc, char *argv[]);

// from fftools/ffprobe.c compiled with -Dmain=ffprobe_main
int ffprobe_main(int argc, char *argv[]);

// Reset FFmpeg global state for re-entrant calls
void ffmpeg_reset(void);

// Set program name for library mode (from patched opt_common.c)
void set_library_program_name(const char *name);

// Install FFmpeg CLI signal handlers.
void term_init(void);

// Request ffmpeg CLI termination without delivering a process signal.
void term_exit(void);

// FFmpeg logging API
void av_log_set_level(int level);

// --- Global state for Swift log callback ---

static ffmpeg_swift_log_func g_swift_log_func = NULL;
static pthread_mutex_t g_exec_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_log_callback_mutex = PTHREAD_MUTEX_INITIALIZER;
static atomic_int g_cancel_requested = 0;

// Optional: default log level if Swift doesn't set it
static int g_log_level = 32; // roughly AV_LOG_INFO

void ffmpeg_set_swift_logger(ffmpeg_swift_log_func func) {
    pthread_mutex_lock(&g_log_callback_mutex);
    g_swift_log_func = func;
    pthread_mutex_unlock(&g_log_callback_mutex);
}

void ffmpeg_set_log_level(int level) {
    g_log_level = level;
    av_log_set_level(level);
}

void ffmpeg_request_cancel(void) {
    atomic_store(&g_cancel_requested, 1);
}

void ffmpeg_clear_cancel(void) {
    atomic_store(&g_cancel_requested, 0);
}

// --- Setup logging once ---

static int g_logging_initialized = 0;

static ffmpeg_swift_log_func ffmpeg_copy_swift_logger(void) {
    ffmpeg_swift_log_func swift_log_func = NULL;
    pthread_mutex_lock(&g_log_callback_mutex);
    swift_log_func = g_swift_log_func;
    pthread_mutex_unlock(&g_log_callback_mutex);
    return swift_log_func;
}

static void ffmpeg_setup_logging_if_needed(void) {
    if (g_logging_initialized) {
        return;
    }
    g_logging_initialized = 1;

    av_log_set_level(g_log_level);
}

// --- Main entrypoint used from Swift ---

int ffmpeg_execute(int argc, char *argv[]) {
    ffmpeg_setup_logging_if_needed();
    ffmpeg_reset();
    set_library_program_name("ffmpeg");
    return ffmpeg_main(argc, argv);
}

int ffprobe_execute(int argc, char *argv[]) {
    ffmpeg_setup_logging_if_needed();
    ffmpeg_reset();
    set_library_program_name("ffprobe");
    return ffprobe_main(argc, argv);
}

// --- Execute with output capture ---

typedef struct {
    int fd;
    char *buffer;
    size_t buffer_size;
    size_t total_read;
    int forward_to_logger;
} output_reader_ctx;

typedef struct {
    atomic_int *done;
} cancel_watcher_ctx;

static void close_if_valid(int fd) {
    if (fd >= 0) {
        close(fd);
    }
}

static void finalize_output_buffer(output_reader_ctx *ctx) {
    if (ctx->buffer && ctx->buffer_size > 0) {
        size_t end = ctx->total_read < (ctx->buffer_size - 1) ? ctx->total_read : (ctx->buffer_size - 1);
        ctx->buffer[end] = '\0';
    }
}

static void forward_output_chunk(output_reader_ctx *ctx, const char *chunk) {
    if (!ctx->forward_to_logger) {
        return;
    }

    ffmpeg_swift_log_func swift_log_func = ffmpeg_copy_swift_logger();
    if (swift_log_func) {
        swift_log_func(g_log_level, chunk);
    }
}

static void drain_output_fd(output_reader_ctx *ctx) {
    char temp[4097];

    while (1) {
        ssize_t bytes_read = read(ctx->fd, temp, sizeof(temp) - 1);
        if (bytes_read <= 0) {
            break;
        }

        temp[bytes_read] = '\0';

        if (ctx->buffer && ctx->buffer_size > 1 && ctx->total_read < (ctx->buffer_size - 1)) {
            size_t remaining = (ctx->buffer_size - 1) - ctx->total_read;
            size_t to_copy = (size_t)bytes_read < remaining ? (size_t)bytes_read : remaining;
            memcpy(ctx->buffer + ctx->total_read, temp, to_copy);
            ctx->total_read += to_copy;
        }

        forward_output_chunk(ctx, temp);
    }

    finalize_output_buffer(ctx);
}

static void *output_reader_thread(void *arg) {
    output_reader_ctx *ctx = (output_reader_ctx *)arg;
    drain_output_fd(ctx);
    return NULL;
}

static void *cancel_watcher_thread(void *arg) {
    cancel_watcher_ctx *ctx = (cancel_watcher_ctx *)arg;
    int cancel_requested = 0;

    while (!atomic_load(ctx->done)) {
        if (!atomic_load(&g_cancel_requested)) {
            usleep(20000);
            continue;
        }

        if (!cancel_requested) {
            term_exit();
            cancel_requested = 1;
        }

        usleep(200000);
    }

    return NULL;
}

static int execute_tool_main(int argc, char *argv[], int (*tool_main)(int, char *[]), const char *program_name) {
    ffmpeg_setup_logging_if_needed();
    ffmpeg_clear_cancel();
    ffmpeg_reset();
    set_library_program_name(program_name);
    term_init();

    atomic_int cancel_done = 0;
    cancel_watcher_ctx cancel_ctx = {
        .done = &cancel_done
    };
    pthread_t cancel_tid;
    int cancel_started = (pthread_create(&cancel_tid, NULL, cancel_watcher_thread, &cancel_ctx) == 0);

    int exit_code = tool_main(argc, argv);

    atomic_store(&cancel_done, 1);
    if (cancel_started) {
        pthread_join(cancel_tid, NULL);
    }

    ffmpeg_clear_cancel();
    return exit_code;
}

static int execute_with_output_common(
    int argc,
    char *argv[],
    char *stdout_buffer,
    size_t stdout_buffer_size,
    char *stderr_buffer,
    size_t stderr_buffer_size,
    int (*tool_main)(int, char *[]),
    const char *program_name
) {
    pthread_mutex_lock(&g_exec_mutex);

    if (stdout_buffer && stdout_buffer_size > 0) {
        stdout_buffer[0] = '\0';
    }
    if (stderr_buffer && stderr_buffer_size > 0) {
        stderr_buffer[0] = '\0';
    }

    if ((!stdout_buffer || stdout_buffer_size == 0) && (!stderr_buffer || stderr_buffer_size == 0)) {
        int code = execute_tool_main(argc, argv, tool_main, program_name);
        pthread_mutex_unlock(&g_exec_mutex);
        return code;
    }

    int stdout_pipe[2] = {-1, -1};
    int stderr_pipe[2] = {-1, -1};
    int stdout_fd = -1;
    int stderr_fd = -1;

    if (pipe(stdout_pipe) < 0 || pipe(stderr_pipe) < 0) {
        close_if_valid(stdout_pipe[0]);
        close_if_valid(stdout_pipe[1]);
        close_if_valid(stderr_pipe[0]);
        close_if_valid(stderr_pipe[1]);
        int code = execute_tool_main(argc, argv, tool_main, program_name);
        pthread_mutex_unlock(&g_exec_mutex);
        return code;
    }

    stdout_fd = dup(STDOUT_FILENO);
    stderr_fd = dup(STDERR_FILENO);
    if (stdout_fd < 0 || stderr_fd < 0) {
        close_if_valid(stdout_fd);
        close_if_valid(stderr_fd);
        close_if_valid(stdout_pipe[0]);
        close_if_valid(stdout_pipe[1]);
        close_if_valid(stderr_pipe[0]);
        close_if_valid(stderr_pipe[1]);
        int code = execute_tool_main(argc, argv, tool_main, program_name);
        pthread_mutex_unlock(&g_exec_mutex);
        return code;
    }

    if (dup2(stdout_pipe[1], STDOUT_FILENO) < 0 || dup2(stderr_pipe[1], STDERR_FILENO) < 0) {
        dup2(stdout_fd, STDOUT_FILENO);
        dup2(stderr_fd, STDERR_FILENO);
        close_if_valid(stdout_fd);
        close_if_valid(stderr_fd);
        close_if_valid(stdout_pipe[0]);
        close_if_valid(stdout_pipe[1]);
        close_if_valid(stderr_pipe[0]);
        close_if_valid(stderr_pipe[1]);
        int code = execute_tool_main(argc, argv, tool_main, program_name);
        pthread_mutex_unlock(&g_exec_mutex);
        return code;
    }

    close_if_valid(stdout_pipe[1]);
    stdout_pipe[1] = -1;
    close_if_valid(stderr_pipe[1]);
    stderr_pipe[1] = -1;

    output_reader_ctx stdout_ctx = {
        .fd = stdout_pipe[0],
        .buffer = stdout_buffer,
        .buffer_size = stdout_buffer_size,
        .total_read = 0,
        .forward_to_logger = 0
    };
    output_reader_ctx stderr_ctx = {
        .fd = stderr_pipe[0],
        .buffer = stderr_buffer,
        .buffer_size = stderr_buffer_size,
        .total_read = 0,
        .forward_to_logger = 1
    };

    pthread_t stdout_reader_tid;
    pthread_t stderr_reader_tid;
    int stdout_reader_started = (pthread_create(&stdout_reader_tid, NULL, output_reader_thread, &stdout_ctx) == 0);
    int stderr_reader_started = (pthread_create(&stderr_reader_tid, NULL, output_reader_thread, &stderr_ctx) == 0);

    int exit_code = execute_tool_main(argc, argv, tool_main, program_name);

    fflush(stdout);
    fflush(stderr);
    dup2(stdout_fd, STDOUT_FILENO);
    dup2(stderr_fd, STDERR_FILENO);
    close_if_valid(stdout_fd);
    close_if_valid(stderr_fd);

    if (stdout_reader_started) {
        pthread_join(stdout_reader_tid, NULL);
    } else {
        drain_output_fd(&stdout_ctx);
    }

    if (stderr_reader_started) {
        pthread_join(stderr_reader_tid, NULL);
    } else {
        drain_output_fd(&stderr_ctx);
    }

    close_if_valid(stdout_pipe[0]);
    close_if_valid(stderr_pipe[0]);
    pthread_mutex_unlock(&g_exec_mutex);
    return exit_code;
}

int ffmpeg_execute_with_output(
    int argc,
    char *argv[],
    char *stdout_buffer,
    size_t stdout_buffer_size,
    char *stderr_buffer,
    size_t stderr_buffer_size
) {
    return execute_with_output_common(
        argc,
        argv,
        stdout_buffer,
        stdout_buffer_size,
        stderr_buffer,
        stderr_buffer_size,
        ffmpeg_main,
        "ffmpeg"
    );
}

int ffprobe_execute_with_output(
    int argc,
    char *argv[],
    char *stdout_buffer,
    size_t stdout_buffer_size,
    char *stderr_buffer,
    size_t stderr_buffer_size
) {
    return execute_with_output_common(
        argc,
        argv,
        stdout_buffer,
        stdout_buffer_size,
        stderr_buffer,
        stderr_buffer_size,
        ffprobe_main,
        "ffprobe"
    );
}
