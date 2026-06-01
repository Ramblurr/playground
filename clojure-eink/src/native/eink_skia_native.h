#ifndef EINK_SKIA_NATIVE_H
#define EINK_SKIA_NATIVE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *eink_skia_last_error(void);

void *eink_skia_create(int width,
                       int height,
                       const char *font_dir,
                       const char *default_family);

int eink_skia_destroy(void *ctx);

int eink_skia_width(void *ctx);
int eink_skia_height(void *ctx);
int eink_skia_stride(void *ctx);

int eink_skia_clear(void *ctx, unsigned char gray);

int eink_skia_save(void *ctx);
int eink_skia_restore(void *ctx);
int eink_skia_translate(void *ctx, float x, float y);
int eink_skia_scale(void *ctx, float sx, float sy);
int eink_skia_clip_rect(void *ctx, float x, float y, float width, float height);

int eink_skia_set_color(void *ctx, float r, float g, float b, float a);
int eink_skia_set_style(void *ctx, int style);
int eink_skia_set_stroke_width(void *ctx, float width);

int eink_skia_draw_rect(void *ctx, float x, float y, float width, float height);
int eink_skia_draw_round_rect(void *ctx, float x, float y, float width, float height, float radius);
int eink_skia_draw_path(void *ctx, const float *xy_pairs, int point_count, int closed);

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
                          float *out_leading);

int eink_skia_draw_text_box(void *ctx,
                            const char *utf8,
                            int utf8_len,
                            const char *family,
                            float size,
                            int weight,
                            int slant,
                            float x,
                            float y,
                            float max_width);

int eink_skia_text_cache_stats(void *ctx,
                               int *out_entries,
                               int *out_hits,
                               int *out_misses,
                               int *out_evictions);

int eink_skia_clear_text_cache(void *ctx);

int eink_skia_replay_commands(void *ctx,
                              const unsigned char *commands,
                              size_t command_len,
                              int command_count);

int eink_skia_copy_gray8(void *ctx, unsigned char *dst, size_t dst_len);

int eink_skia_present(void *ctx,
                      int x,
                      int y,
                      int width,
                      int height,
                      int waveform,
                      int flash,
                      int wait);

#ifdef __cplusplus
}
#endif

#endif // EINK_SKIA_NATIVE_H
