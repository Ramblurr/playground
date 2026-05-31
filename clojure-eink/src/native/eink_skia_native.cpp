#include "eink_skia_native.h"

#include <cerrno>
#include <cstdarg>
#include <cstdio>

namespace {

thread_local char last_error[512] = "";

void set_error(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(last_error, sizeof(last_error), fmt, ap);
    va_end(ap);
}

int not_implemented(const char *function_name) {
    set_error("%s: not implemented", function_name);
    return -ENOSYS;
}

} // namespace

const char *eink_skia_last_error(void) {
    return last_error;
}

void *eink_skia_create(int width,
                       int height,
                       const char *font_dir,
                       const char *default_family) {
    (void)width;
    (void)height;
    (void)font_dir;
    (void)default_family;
    not_implemented("eink_skia_create");
    return nullptr;
}

int eink_skia_destroy(void *ctx) {
    (void)ctx;
    return not_implemented("eink_skia_destroy");
}

int eink_skia_width(void *ctx) {
    (void)ctx;
    return not_implemented("eink_skia_width");
}

int eink_skia_height(void *ctx) {
    (void)ctx;
    return not_implemented("eink_skia_height");
}

int eink_skia_stride(void *ctx) {
    (void)ctx;
    return not_implemented("eink_skia_stride");
}

int eink_skia_clear(void *ctx, unsigned char gray) {
    (void)ctx;
    (void)gray;
    return not_implemented("eink_skia_clear");
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
    (void)ctx;
    (void)dst;
    (void)dst_len;
    return not_implemented("eink_skia_copy_gray8");
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
