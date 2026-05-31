#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "fbink.h"

#define EINK_MAX_INPUT_DEVICES 8

typedef struct {
    int64_t sec;
    int64_t usec;
    int32_t type;
    int32_t code;
    int32_t value;
    int32_t device_index;
    uint32_t device_type;
    uint32_t reserved;
} EinkInputEvent;

_Static_assert(sizeof(EinkInputEvent) == 40, "EinkInputEvent must be 40 bytes");

struct eink_input_device {
    int fd;
    bool grabbed;
    uint32_t type;
    char path[4096];
    char name[256];
};

struct eink_context {
    int fd;
    bool initialized;
    FBInkConfig cfg;
    FBInkState state;
    bool input_initialized;
    size_t input_count;
    struct eink_input_device input_devices[EINK_MAX_INPUT_DEVICES];
    char last_error[512];
};

static struct eink_context ctx = {
    .fd = -1,
};

static void set_error(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(ctx.last_error, sizeof(ctx.last_error), fmt, ap);
    va_end(ap);
}

static int fail_with_errno(const char *what, int code) {
    set_error("%s: %s", what, strerror(code));
    return -code;
}

const char *eink_last_error(void) {
    if (ctx.last_error[0] == '\0') {
        return "";
    }
    return ctx.last_error;
}

static void clear_input_device(struct eink_input_device *dev) {
    memset(dev, 0, sizeof(*dev));
    dev->fd = -1;
}

static void reset_input_devices(void) {
    for (size_t i = 0; i < EINK_MAX_INPUT_DEVICES; i++) {
        clear_input_device(&ctx.input_devices[i]);
    }
    ctx.input_count = 0;
    ctx.input_initialized = false;
}

static void close_input_device_at(size_t index) {
    if (index >= ctx.input_count) {
        return;
    }

    struct eink_input_device *dev = &ctx.input_devices[index];
    if (dev->fd >= 0) {
        if (dev->grabbed) {
            ioctl(dev->fd, EVIOCGRAB, 0);
        }
        close(dev->fd);
    }

    for (size_t i = index; i + 1 < ctx.input_count; i++) {
        ctx.input_devices[i] = ctx.input_devices[i + 1];
    }
    ctx.input_count--;
    clear_input_device(&ctx.input_devices[ctx.input_count]);
    if (ctx.input_count == 0) {
        ctx.input_initialized = false;
    }
}

static void close_fbink_input_devices(FBInkInputDevice *devices, size_t dev_count) {
    if (devices == NULL) {
        return;
    }

    for (size_t i = 0; i < dev_count; i++) {
        if (devices[i].fd >= 0) {
            close(devices[i].fd);
            devices[i].fd = -1;
        }
    }
}

int eink_input_event_size(void) {
    return (int)sizeof(EinkInputEvent);
}

int eink_input_close(void) {
    while (ctx.input_count > 0) {
        close_input_device_at(ctx.input_count - 1);
    }
    reset_input_devices();
    ctx.last_error[0] = '\0';
    return 0;
}

int eink_input_open_scan(int grab, int verbose) {
    eink_input_close();

    size_t dev_count = 0;
    INPUT_DEVICE_TYPE_T match = INPUT_TOUCHSCREEN | INPUT_TABLET | INPUT_POWER_BUTTON | INPUT_SLEEP_COVER | INPUT_PAGINATION_BUTTONS;
    INPUT_DEVICE_TYPE_T exclude = INPUT_KEYBOARD;
    INPUT_SETTINGS_TYPE_T settings = verbose ? 0 : NO_RECAP;
    FBInkInputDevice *devices = fbink_input_scan(match, exclude, settings, &dev_count);
    if (devices == NULL) {
        return fail_with_errno("fbink_input_scan", errno ? errno : ENODEV);
    }

    for (size_t i = 0; i < dev_count; i++) {
        FBInkInputDevice *src = &devices[i];
        if (!src->matched || src->fd < 0) {
            continue;
        }

        if (ctx.input_count >= EINK_MAX_INPUT_DEVICES) {
            close(src->fd);
            src->fd = -1;
            continue;
        }

        struct eink_input_device *dst = &ctx.input_devices[ctx.input_count];
        clear_input_device(dst);
        dst->fd = src->fd;
        dst->type = src->type;
        snprintf(dst->path, sizeof(dst->path), "%s", src->path);
        snprintf(dst->name, sizeof(dst->name), "%s", src->name);
        src->fd = -1;

        if (grab != 0) {
            if (ioctl(dst->fd, EVIOCGRAB, 1) < 0) {
                int saved = errno ? errno : EIO;
                close(dst->fd);
                clear_input_device(dst);
                close_fbink_input_devices(devices, dev_count);
                free(devices);
                eink_input_close();
                return fail_with_errno("EVIOCGRAB", saved);
            }
            dst->grabbed = true;
        }

        ctx.input_count++;
    }

    close_fbink_input_devices(devices, dev_count);
    free(devices);

    if (ctx.input_count == 0) {
        set_error("eink_input_open_scan: no matched input devices");
        return -ENODEV;
    }

    ctx.input_initialized = true;
    ctx.last_error[0] = '\0';
    return (int)ctx.input_count;
}

int eink_input_device_count(void) {
    return (int)ctx.input_count;
}

const char *eink_input_device_path(int index) {
    if (index < 0 || (size_t)index >= ctx.input_count) {
        set_error("eink_input_device_path: invalid index %d", index);
        return NULL;
    }
    return ctx.input_devices[index].path;
}

const char *eink_input_device_name(int index) {
    if (index < 0 || (size_t)index >= ctx.input_count) {
        set_error("eink_input_device_name: invalid index %d", index);
        return NULL;
    }
    return ctx.input_devices[index].name;
}

int eink_input_device_type(int index) {
    if (index < 0 || (size_t)index >= ctx.input_count) {
        set_error("eink_input_device_type: invalid index %d", index);
        return -EINVAL;
    }
    return (int)ctx.input_devices[index].type;
}

static void copy_input_event(EinkInputEvent *dst, const struct input_event *src, int device_index, uint32_t device_type) {
    dst->sec = (int64_t)src->input_event_sec;
    dst->usec = (int64_t)src->input_event_usec;
    dst->type = (int32_t)src->type;
    dst->code = (int32_t)src->code;
    dst->value = (int32_t)src->value;
    dst->device_index = (int32_t)device_index;
    dst->device_type = device_type;
    dst->reserved = 0;
}

int eink_input_poll(EinkInputEvent *out, int capacity, int timeout_ms) {
    if (out == NULL || capacity <= 0) {
        set_error("eink_input_poll: invalid output buffer or capacity");
        return -EINVAL;
    }
    if (ctx.input_count == 0) {
        set_error("eink_input_poll: no open input devices");
        return -ENODEV;
    }

    struct pollfd fds[EINK_MAX_INPUT_DEVICES];
    for (size_t i = 0; i < ctx.input_count; i++) {
        fds[i].fd = ctx.input_devices[i].fd;
        fds[i].events = POLLIN;
        fds[i].revents = 0;
    }

    int rv;
    do {
        rv = poll(fds, ctx.input_count, timeout_ms);
    } while (rv < 0 && errno == EINTR);

    if (rv == 0) {
        return 0;
    }
    if (rv < 0) {
        return fail_with_errno("poll", errno ? errno : EIO);
    }

    int copied = 0;
    for (size_t i = 0; i < ctx.input_count && copied < capacity; i++) {
        if (!(fds[i].revents & (POLLIN | POLLERR | POLLHUP | POLLNVAL))) {
            continue;
        }
        if (fds[i].revents & POLLNVAL) {
            close_input_device_at(i);
            return fail_with_errno("poll input fd", ENODEV);
        }

        for (;;) {
            struct input_event ev;
            ssize_t n = read(ctx.input_devices[i].fd, &ev, sizeof(ev));
            if (n == (ssize_t)sizeof(ev)) {
                copy_input_event(&out[copied], &ev, (int)i, ctx.input_devices[i].type);
                copied++;
                if (copied >= capacity) {
                    ctx.last_error[0] = '\0';
                    return copied;
                }
                continue;
            }

            if (n < 0 && errno == EINTR) {
                continue;
            }
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                break;
            }
            if (n < 0 && errno == ENODEV) {
                close_input_device_at(i);
                return fail_with_errno("read input fd", ENODEV);
            }
            if (n == 0) {
                return fail_with_errno("read input fd", EPIPE);
            }
            return fail_with_errno("read input fd", n < 0 ? errno : EINVAL);
        }
    }

    ctx.last_error[0] = '\0';
    return copied;
}

static WFM_MODE_INDEX_T decode_waveform(int waveform) {
    switch (waveform) {
        case 1:
            return WFM_DU;
        case 2:
            return WFM_GC16;
        case 3:
            return WFM_GL16;
        case 4:
            return WFM_A2;
        case 0:
        default:
            return WFM_AUTO;
    }
}

int eink_init(int quiet, int verbose) {
    if (ctx.initialized) {
        return 0;
    }

    eink_input_close();
    memset(&ctx, 0, sizeof(ctx));
    ctx.fd = -1;
    reset_input_devices();
    ctx.cfg.is_quiet = quiet != 0;
    ctx.cfg.is_verbose = verbose != 0;

    ctx.fd = fbink_open();
    if (ctx.fd < 0) {
        return fail_with_errno("fbink_open", errno ? errno : ENODEV);
    }

    int rv = fbink_init(ctx.fd, &ctx.cfg);
    if (rv != EXIT_SUCCESS) {
        int saved = errno ? errno : EIO;
        fbink_close(ctx.fd);
        ctx.fd = -1;
        return fail_with_errno("fbink_init", saved);
    }

    fbink_get_state(&ctx.cfg, &ctx.state);
    ctx.initialized = true;
    return 0;
}

int eink_close(void) {
    int rv = 0;
    eink_input_close();
    if (ctx.fd >= 0) {
        rv = fbink_close(ctx.fd);
    }
    ctx.fd = -1;
    ctx.initialized = false;
    return rv == EXIT_SUCCESS ? 0 : -EIO;
}

int eink_screen_width(void) {
    return ctx.initialized ? (int)ctx.state.screen_width : -ENODEV;
}

int eink_screen_height(void) {
    return ctx.initialized ? (int)ctx.state.screen_height : -ENODEV;
}

int eink_view_width(void) {
    return ctx.initialized ? (int)ctx.state.view_width : -ENODEV;
}

int eink_view_height(void) {
    return ctx.initialized ? (int)ctx.state.view_height : -ENODEV;
}

int eink_present_gray8(const uint8_t *data,
                       int width,
                       int height,
                       int stride,
                       int x,
                       int y,
                       int waveform,
                       int flash,
                       int wait) {
    if (!ctx.initialized || ctx.fd < 0) {
        set_error("eink_present_gray8: not initialized");
        return -ENODEV;
    }
    if (data == NULL) {
        set_error("eink_present_gray8: data is NULL");
        return -EINVAL;
    }
    if (width <= 0 || height <= 0 || stride < width) {
        set_error("eink_present_gray8: invalid geometry width=%d height=%d stride=%d", width, height, stride);
        return -EINVAL;
    }

    size_t row_bytes = (size_t)width;
    size_t rows = (size_t)height;
    if (row_bytes != 0 && rows > SIZE_MAX / row_bytes) {
        set_error("eink_present_gray8: image size overflow");
        return -EOVERFLOW;
    }
    size_t compact_len = row_bytes * rows;

    const uint8_t *src = data;
    uint8_t *compact = NULL;
    if (stride != width) {
        compact = malloc(compact_len);
        if (compact == NULL) {
            return fail_with_errno("malloc", errno ? errno : ENOMEM);
        }
        for (int row = 0; row < height; row++) {
            memcpy(compact + ((size_t)row * row_bytes), data + ((size_t)row * (size_t)stride), row_bytes);
        }
        src = compact;
    }

    FBInkConfig cfg = ctx.cfg;
    cfg.wfm_mode = decode_waveform(waveform);
    cfg.is_flashing = flash != 0;
    cfg.ignore_alpha = true;

    int rv = fbink_print_raw_data(ctx.fd, src, width, height, compact_len, (short int)x, (short int)y, &cfg);
    free(compact);

    if (rv < 0) {
        int saved = errno ? errno : EIO;
        set_error("fbink_print_raw_data failed with rv=%d errno=%d (%s)", rv, saved, strerror(saved));
        return rv;
    }

    if (wait != 0) {
        int wrv = fbink_wait_for_complete(ctx.fd, LAST_MARKER);
        if (wrv != EXIT_SUCCESS && wrv != -ENOSYS && wrv != -EINVAL) {
            int saved = errno ? errno : EIO;
            set_error("fbink_wait_for_complete failed with rv=%d errno=%d (%s)", wrv, saved, strerror(saved));
            return wrv;
        }
    }

    ctx.last_error[0] = '\0';
    return 0;
}
