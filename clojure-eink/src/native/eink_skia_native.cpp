#include "eink_skia_native.h"

#include <algorithm>
#include <cerrno>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <new>
#include <string>
#include <vector>

namespace {

thread_local char last_error[512] = "";

struct eink_skia_context {
    int width;
    int height;
    int stride;
    std::vector<uint8_t> pixels;
    std::vector<uint8_t> previous_pixels;
    std::string default_family;
};

void set_error(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(last_error, sizeof(last_error), fmt, ap);
    va_end(ap);
}

void clear_error() {
    last_error[0] = '\0';
}

int fail_with_code(int code, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(last_error, sizeof(last_error), fmt, ap);
    va_end(ap);
    return -code;
}

int not_implemented(const char *function_name) {
    return fail_with_code(ENOSYS, "%s: not implemented", function_name);
}

bool checked_buffer_len(int width, int height, size_t *out_len) {
    if (width <= 0 || height <= 0) {
        return false;
    }

    size_t row_bytes = static_cast<size_t>(width);
    size_t rows = static_cast<size_t>(height);
    if (rows > std::numeric_limits<size_t>::max() / row_bytes) {
        return false;
    }

    *out_len = row_bytes * rows;
    return true;
}

eink_skia_context *as_context(void *ctx, const char *function_name) {
    if (ctx == nullptr) {
        set_error("%s: context is NULL", function_name);
        return nullptr;
    }
    return static_cast<eink_skia_context *>(ctx);
}

} // namespace

const char *eink_skia_last_error(void) {
    return last_error;
}

void *eink_skia_create(int width,
                       int height,
                       const char *font_dir,
                       const char *default_family) {
    (void)font_dir;

    size_t pixel_count = 0;
    if (!checked_buffer_len(width, height, &pixel_count)) {
        set_error("eink_skia_create: invalid dimensions width=%d height=%d", width, height);
        return nullptr;
    }

    try {
        auto *ctx = new eink_skia_context();
        ctx->width = width;
        ctx->height = height;
        ctx->stride = width;
        ctx->pixels.assign(pixel_count, 0xFF);
        ctx->previous_pixels.assign(pixel_count, 0xFF);
        ctx->default_family = default_family != nullptr ? default_family : "";
        clear_error();
        return ctx;
    } catch (const std::bad_alloc &) {
        set_error("eink_skia_create: allocation failed for width=%d height=%d", width, height);
        return nullptr;
    } catch (...) {
        set_error("eink_skia_create: unexpected error");
        return nullptr;
    }
}

int eink_skia_destroy(void *ctx) {
    eink_skia_context *context = as_context(ctx, "eink_skia_destroy");
    if (context == nullptr) {
        return -EINVAL;
    }

    delete context;
    clear_error();
    return 0;
}

int eink_skia_width(void *ctx) {
    eink_skia_context *context = as_context(ctx, "eink_skia_width");
    if (context == nullptr) {
        return -EINVAL;
    }

    clear_error();
    return context->width;
}

int eink_skia_height(void *ctx) {
    eink_skia_context *context = as_context(ctx, "eink_skia_height");
    if (context == nullptr) {
        return -EINVAL;
    }

    clear_error();
    return context->height;
}

int eink_skia_stride(void *ctx) {
    eink_skia_context *context = as_context(ctx, "eink_skia_stride");
    if (context == nullptr) {
        return -EINVAL;
    }

    clear_error();
    return context->stride;
}

int eink_skia_clear(void *ctx, unsigned char gray) {
    eink_skia_context *context = as_context(ctx, "eink_skia_clear");
    if (context == nullptr) {
        return -EINVAL;
    }

    std::fill(context->pixels.begin(), context->pixels.end(), static_cast<uint8_t>(gray));
    clear_error();
    return 0;
}

int eink_skia_save(void *ctx) {
    (void)ctx;
    return not_implemented("eink_skia_save");
}

int eink_skia_restore(void *ctx) {
    (void)ctx;
    return not_implemented("eink_skia_restore");
}

int eink_skia_translate(void *ctx, float x, float y) {
    (void)ctx;
    (void)x;
    (void)y;
    return not_implemented("eink_skia_translate");
}

int eink_skia_scale(void *ctx, float sx, float sy) {
    (void)ctx;
    (void)sx;
    (void)sy;
    return not_implemented("eink_skia_scale");
}

int eink_skia_clip_rect(void *ctx, float x, float y, float width, float height) {
    (void)ctx;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
    return not_implemented("eink_skia_clip_rect");
}

int eink_skia_set_color(void *ctx, float r, float g, float b, float a) {
    (void)ctx;
    (void)r;
    (void)g;
    (void)b;
    (void)a;
    return not_implemented("eink_skia_set_color");
}

int eink_skia_set_style(void *ctx, int style) {
    (void)ctx;
    (void)style;
    return not_implemented("eink_skia_set_style");
}

int eink_skia_set_stroke_width(void *ctx, float width) {
    (void)ctx;
    (void)width;
    return not_implemented("eink_skia_set_stroke_width");
}

int eink_skia_draw_rect(void *ctx, float x, float y, float width, float height) {
    (void)ctx;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
    return not_implemented("eink_skia_draw_rect");
}

int eink_skia_draw_round_rect(void *ctx, float x, float y, float width, float height, float radius) {
    (void)ctx;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
    (void)radius;
    return not_implemented("eink_skia_draw_round_rect");
}

int eink_skia_draw_path(void *ctx, const float *xy_pairs, int point_count, int closed) {
    (void)ctx;
    (void)xy_pairs;
    (void)point_count;
    (void)closed;
    return not_implemented("eink_skia_draw_path");
}

int eink_skia_text_bounds(void *ctx,
                          const char *utf8,
                          int utf8_len,
                          const char *family,
                          float size,
                          int weight,
                          int slant,
                          float max_width,
                          float *out_width,
                          float *out_height,
                          float *out_ascent,
                          float *out_descent,
                          float *out_leading) {
    (void)ctx;
    (void)utf8;
    (void)utf8_len;
    (void)family;
    (void)size;
    (void)weight;
    (void)slant;
    (void)max_width;
    (void)out_width;
    (void)out_height;
    (void)out_ascent;
    (void)out_descent;
    (void)out_leading;
    return not_implemented("eink_skia_text_bounds");
}

int eink_skia_draw_text_box(void *ctx,
                            const char *utf8,
                            int utf8_len,
                            const char *family,
                            float size,
                            int weight,
                            int slant,
                            float x,
                            float y,
                            float max_width) {
    (void)ctx;
    (void)utf8;
    (void)utf8_len;
    (void)family;
    (void)size;
    (void)weight;
    (void)slant;
    (void)x;
    (void)y;
    (void)max_width;
    return not_implemented("eink_skia_draw_text_box");
}

int eink_skia_copy_gray8(void *ctx, unsigned char *dst, size_t dst_len) {
    eink_skia_context *context = as_context(ctx, "eink_skia_copy_gray8");
    if (context == nullptr) {
        return -EINVAL;
    }
    if (dst == nullptr) {
        return fail_with_code(EINVAL, "eink_skia_copy_gray8: dst is NULL");
    }

    size_t required_len = context->pixels.size();
    if (dst_len < required_len) {
        return fail_with_code(EINVAL,
                              "eink_skia_copy_gray8: undersized dst_len=%zu required=%zu",
                              dst_len,
                              required_len);
    }

    std::memcpy(dst, context->pixels.data(), required_len);
    clear_error();
    return 0;
}

int eink_skia_present(void *ctx,
                      int x,
                      int y,
                      int width,
                      int height,
                      int waveform,
                      int flash,
                      int wait) {
    (void)ctx;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
    (void)waveform;
    (void)flash;
    (void)wait;
    return not_implemented("eink_skia_present");
}
