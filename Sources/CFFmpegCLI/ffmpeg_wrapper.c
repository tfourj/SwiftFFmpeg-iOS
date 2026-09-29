#include "ffmpeg_wrapper.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <errno.h>
#include <stdarg.h>

// --- Forward declarations from FFmpeg (we don't include FFmpeg headers) ---

// from fftools/ffmpeg.c compiled with -Dmain=ffmpeg_main
int ffmpeg_main(int argc, char *argv[]);

// from fftools/ffprobe.c compiled with -Dmain=ffprobe_main
int ffprobe_main(int argc, char *argv[]);

// Reset FFmpeg global state for re-entrant calls
void ffmpeg_reset(void);
void ffprobe_reset(void);

// Set program name for library mode (from patched opt_common.c)
void set_library_program_name(const char *name);

// FFmpeg logging API
void av_log_set_level(int level);
void av_log_set_callback(void (*callback)(void *, int, const char *, va_list));
void av_log_default_callback(void *avcl, int level, const char *fmt, va_list vl);

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

// Polled by the patched FFmpeg scheduler and I/O interrupt callback.
int ffmpeg_library_cancel_requested(void) {
    return atomic_load(&g_cancel_requested);
}

void ffmpeg_clear_cancel(void) {
    atomic_store(&g_cancel_requested, 0);
}

// --- Logging state ---

static ffmpeg_swift_log_func ffmpeg_copy_swift_logger(void) {
    ffmpeg_swift_log_func swift_log_func = NULL;
    pthread_mutex_lock(&g_log_callback_mutex);
    swift_log_func = g_swift_log_func;
    pthread_mutex_unlock(&g_log_callback_mutex);
    return swift_log_func;
}

// Listing options such as -version and -bsfs install FFmpeg's help logger,
// which prints every level to stdout, and -v changes the process-wide level.
// A CLI process exits before either leaks, so start every call from defaults.
static void ffmpeg_reset_logging(void) {
    av_log_set_callback(av_log_default_callback);
    av_log_set_level(g_log_level);
}

// --- Main entrypoint used from Swift ---

int ffmpeg_execute(int argc, char *argv[]) {
    ffmpeg_reset_logging();
    ffmpeg_reset();
    set_library_program_name("ffmpeg");
    return ffmpeg_main(argc, argv);
}

int ffprobe_execute(int argc, char *argv[]) {
    ffmpeg_reset_logging();
    ffprobe_reset();
    set_library_program_name("ffprobe");
    return ffprobe_main(argc, argv);
}

// --- Execute with output capture ---

// Space kept between the start and end of a truncated log for the marker line.
#define OUTPUT_TRUNCATION_MARKER_RESERVE 64

typedef struct {
    int fd;
    char *buffer;
    size_t buffer_size;
    size_t total_read;
    int forward_to_logger;
    // Logs also keep their end in a ring buffer, because the error is the last line.
    size_t head_capacity;
    char *tail;
    size_t tail_capacity;
    size_t tail_start;
    size_t tail_length;
    size_t dropped;
} output_reader_ctx;

static void init_output_reader(output_reader_ctx *ctx, int fd, char *buffer, size_t buffer_size, int is_log) {
    memset(ctx, 0, sizeof(*ctx));
    ctx->fd = fd;
    ctx->buffer = buffer;
    ctx->buffer_size = buffer_size;
    ctx->forward_to_logger = is_log;

    size_t capacity = buffer && buffer_size > 0 ? buffer_size - 1 : 0;
    ctx->head_capacity = capacity;
    if (!is_log || capacity < 4 * OUTPUT_TRUNCATION_MARKER_RESERVE) {
        return;
    }

    size_t head_capacity = capacity / 4;
    size_t tail_capacity = capacity - head_capacity - OUTPUT_TRUNCATION_MARKER_RESERVE;
    ctx->tail = malloc(tail_capacity);
    if (ctx->tail) {
        ctx->head_capacity = head_capacity;
        ctx->tail_capacity = tail_capacity;
    }
}

static void store_output_bytes(output_reader_ctx *ctx, const char *bytes, size_t length) {
    if (ctx->total_read < ctx->head_capacity) {
        size_t remaining = ctx->head_capacity - ctx->total_read;
        size_t to_copy = length < remaining ? length : remaining;
        memcpy(ctx->buffer + ctx->total_read, bytes, to_copy);
        ctx->total_read += to_copy;
        bytes += to_copy;
        length -= to_copy;
    }
    if (length == 0) {
        return;
    }
    if (!ctx->tail) {
        ctx->dropped += length;
        return;
    }

    size_t capacity = ctx->tail_capacity;
    if (length >= capacity) {
        ctx->dropped += ctx->tail_length + (length - capacity);
        memcpy(ctx->tail, bytes + (length - capacity), capacity);
        ctx->tail_start = 0;
        ctx->tail_length = capacity;
        return;
    }

    if (ctx->tail_length + length > capacity) {
        size_t overflow = ctx->tail_length + length - capacity;
        ctx->tail_start = (ctx->tail_start + overflow) % capacity;
        ctx->tail_length -= overflow;
        ctx->dropped += overflow;
    }
    size_t write_position = (ctx->tail_start + ctx->tail_length) % capacity;
    size_t first_part = length < capacity - write_position ? length : capacity - write_position;
    memcpy(ctx->tail + write_position, bytes, first_part);
    memcpy(ctx->tail, bytes + first_part, length - first_part);
    ctx->tail_length += length;
}

static int is_line_break(char character) {
    return character == '\n' || character == '\r';
}

static void close_if_valid(int fd) {
    if (fd >= 0) {
        close(fd);
    }
}

// Writes the kept start, a marker when output was dropped, and the kept end.
// Cuts land on line breaks so the marker sits between whole lines.
static void finalize_output_buffer(output_reader_ctx *ctx) {
    if (!ctx->buffer || ctx->buffer_size == 0) {
        free(ctx->tail);
        ctx->tail = NULL;
        return;
    }

    size_t end = ctx->total_read;
    size_t skip = 0;
    if (ctx->dropped > 0 && ctx->tail_length > 0) {
        size_t head_end = end;
        while (head_end > 0 && !is_line_break(ctx->buffer[head_end - 1])) {
            head_end--;
        }
        if (head_end > 0) {
            ctx->dropped += end - head_end;
            end = head_end;
        }

        while (skip < ctx->tail_length
               && !is_line_break(ctx->tail[(ctx->tail_start + skip) % ctx->tail_capacity])) {
            skip++;
        }
        skip = skip < ctx->tail_length ? skip + 1 : 0;
        ctx->dropped += skip;

        int written = snprintf(
            ctx->buffer + end,
            OUTPUT_TRUNCATION_MARKER_RESERVE,
            "\n[... %zu bytes truncated ...]\n",
            ctx->dropped
        );
        if (written > 0) {
            end += (size_t)written < OUTPUT_TRUNCATION_MARKER_RESERVE
                ? (size_t)written
                : OUTPUT_TRUNCATION_MARKER_RESERVE - 1;
        }
    }

    for (size_t index = skip; index < ctx->tail_length; index++) {
        ctx->buffer[end++] = ctx->tail[(ctx->tail_start + index) % ctx->tail_capacity];
    }
    ctx->buffer[end] = '\0';

    free(ctx->tail);
    ctx->tail = NULL;
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

        store_output_bytes(ctx, temp, (size_t)bytes_read);

        forward_output_chunk(ctx, temp);
    }

    finalize_output_buffer(ctx);
}

static void *output_reader_thread(void *arg) {
    output_reader_ctx *ctx = (output_reader_ctx *)arg;
    drain_output_fd(ctx);
    return NULL;
}

static int execute_tool_main(int argc, char *argv[], int (*tool_main)(int, char *[]), const char *program_name) {
    ffmpeg_reset_logging();
    ffmpeg_clear_cancel();
    if (strcmp(program_name, "ffprobe") == 0) {
        ffprobe_reset();
    } else {
        ffmpeg_reset();
    }
    set_library_program_name(program_name);

    int exit_code;
    if (strcmp(program_name, "ffmpeg") == 0) {
        // FFmpeg's process-oriented startup banner is not re-entrant. Inject
        // the public option for every embedded call while preserving argv[0].
        char **embedded_argv = calloc((size_t)argc + 2, sizeof(*embedded_argv));
        if (!embedded_argv) {
            exit_code = -ENOMEM;
        } else {
            embedded_argv[0] = argv[0];
            embedded_argv[1] = "-hide_banner";
            for (int i = 1; i < argc; i++)
                embedded_argv[i + 1] = argv[i];
            exit_code = tool_main(argc + 1, embedded_argv);
            free(embedded_argv);
        }
    } else {
        exit_code = tool_main(argc, argv);
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

    // stdout carries data read from its start, so only the log keeps its end.
    output_reader_ctx stdout_ctx;
    output_reader_ctx stderr_ctx;
    init_output_reader(&stdout_ctx, stdout_pipe[0], stdout_buffer, stdout_buffer_size, 0);
    init_output_reader(&stderr_ctx, stderr_pipe[0], stderr_buffer, stderr_buffer_size, 1);

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
