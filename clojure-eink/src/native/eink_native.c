#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fbink.h"

struct eink_context {
    int fd;
    bool initialized;
    FBInkConfig cfg;
    FBInkState state;
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

    memset(&ctx, 0, sizeof(ctx));
    ctx.fd = -1;
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
