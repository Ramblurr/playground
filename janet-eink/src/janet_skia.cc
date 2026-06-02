#include <algorithm>
#include <cerrno>
#include <climits>
#include <cstddef>
#include <cstdint>
#include <cstring>

#include <janet.h>
#include "fbink.h"

#include "core/SkBitmap.h"
#include "core/SkCanvas.h"
#include "core/SkColor.h"
#include "core/SkImageInfo.h"
#include "core/SkPaint.h"
#include "core/SkRect.h"

namespace {

constexpr int kGlyphWidth = 5;
constexpr int kGlyphHeight = 7;
constexpr int kGlyphGap = 1;
constexpr const char *kHelloText = "Hello Skia!";

struct Glyph {
    char ch;
    const char *rows[kGlyphHeight];
};

constexpr Glyph kGlyphs[] = {
    {' ', {"00000", "00000", "00000", "00000", "00000", "00000", "00000"}},
    {'!', {"00100", "00100", "00100", "00100", "00100", "00000", "00100"}},
    {'H', {"10001", "10001", "10001", "11111", "10001", "10001", "10001"}},
    {'S', {"01111", "10000", "10000", "01110", "00001", "00001", "11110"}},
    {'a', {"00000", "01110", "00001", "01111", "10001", "10011", "01101"}},
    {'e', {"00000", "01110", "10001", "11111", "10000", "10001", "01110"}},
    {'i', {"00100", "00000", "01100", "00100", "00100", "00100", "01110"}},
    {'k', {"10001", "10010", "10100", "11000", "10100", "10010", "10001"}},
    {'l', {"01100", "00100", "00100", "00100", "00100", "00100", "01110"}},
    {'o', {"00000", "01110", "10001", "10001", "10001", "10001", "01110"}},
};

const char *const *glyph_rows(char ch) {
    for (const Glyph &glyph : kGlyphs) {
        if (glyph.ch == ch) {
            return glyph.rows;
        }
    }
    return kGlyphs[0].rows;
}

int text_columns(const char *text) {
    const size_t len = std::strlen(text);
    if (len == 0) {
        return 0;
    }
    return static_cast<int>(len) * kGlyphWidth + static_cast<int>(len - 1) * kGlyphGap;
}

struct RenderStats {
    int black_pixels = 0;
};

void draw_block_text(SkCanvas &canvas, const char *text, int x, int y, int scale, const SkPaint &paint) {
    int cursor_x = x;
    for (const char *p = text; *p != '\0'; ++p) {
        const char *const *rows = glyph_rows(*p);
        for (int row = 0; row < kGlyphHeight; ++row) {
            for (int col = 0; col < kGlyphWidth; ++col) {
                if (rows[row][col] == '1') {
                    canvas.drawRect(
                        SkRect::MakeXYWH(
                            static_cast<SkScalar>(cursor_x + col * scale),
                            static_cast<SkScalar>(y + row * scale),
                            static_cast<SkScalar>(scale),
                            static_cast<SkScalar>(scale)),
                        paint);
                }
            }
        }
        cursor_x += (kGlyphWidth + kGlyphGap) * scale;
    }
}

int count_black_pixels(const SkBitmap &bitmap) {
    const int width = bitmap.width();
    const int height = bitmap.height();
    int count = 0;
    for (int y = 0; y < height; ++y) {
        const uint8_t *row = static_cast<const uint8_t *>(bitmap.getAddr(0, y));
        for (int x = 0; x < width; ++x) {
            const uint8_t r = row[x * 4 + 0];
            const uint8_t g = row[x * 4 + 1];
            const uint8_t b = row[x * 4 + 2];
            if (r < 128 && g < 128 && b < 128) {
                ++count;
            }
        }
    }
    return count;
}

bool render_hello_bitmap(int width, int height, SkBitmap *bitmap, RenderStats *stats) {
    if (width <= 0 || height <= 0) {
        return false;
    }

    const SkImageInfo info = SkImageInfo::Make(
        width,
        height,
        kRGBA_8888_SkColorType,
        kOpaque_SkAlphaType);
    const size_t row_bytes = static_cast<size_t>(width) * 4U;
    if (!bitmap->tryAllocPixels(info, row_bytes)) {
        return false;
    }

    SkCanvas canvas(*bitmap);
    canvas.clear(SK_ColorWHITE);

    const int columns = text_columns(kHelloText);
    const int scale_x = std::max(1, width / (columns + 6));
    const int scale_y = std::max(1, height / (kGlyphHeight + 10));
    const int scale = std::max(1, std::min(scale_x, scale_y));
    const int text_width = columns * scale;
    const int text_height = kGlyphHeight * scale;
    const int text_x = std::max(0, (width - text_width) / 2);
    const int text_y = std::max(0, (height - text_height) / 2);
    const int padding = std::max(4, scale * 2);

    SkPaint black_fill;
    black_fill.setAntiAlias(false);
    black_fill.setColor(SK_ColorBLACK);
    black_fill.setStyle(SkPaint::kFill_Style);

    SkPaint black_stroke;
    black_stroke.setAntiAlias(false);
    black_stroke.setColor(SK_ColorBLACK);
    black_stroke.setStyle(SkPaint::kStroke_Style);
    black_stroke.setStrokeWidth(static_cast<SkScalar>(std::max(2, scale / 3)));

    const SkScalar frame_left = static_cast<SkScalar>(std::max(0, text_x - padding));
    const SkScalar frame_top = static_cast<SkScalar>(std::max(0, text_y - padding));
    const SkScalar frame_right = static_cast<SkScalar>(std::min(width, text_x + text_width + padding));
    const SkScalar frame_bottom = static_cast<SkScalar>(std::min(height, text_y + text_height + padding));
    canvas.drawRect(SkRect::MakeLTRB(frame_left, frame_top, frame_right, frame_bottom), black_stroke);
    draw_block_text(canvas, kHelloText, text_x, text_y, scale, black_fill);

    if (stats != nullptr) {
        stats->black_pixels = count_black_pixels(*bitmap);
    }
    return true;
}

void close_or_panic(int fbfd) {
    const int close_rv = fbink_close(fbfd);
    if (close_rv < 0) {
        const int saved = errno;
        janet_panicf("fbink_close failed: rv=%d errno=%d (%s)", close_rv, saved, std::strerror(saved));
    }
}

}  // namespace

static Janet cfun_self_test(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 0);
    (void) argv;

    SkBitmap bitmap;
    RenderStats stats;
    if (!render_hello_bitmap(640, 480, &bitmap, &stats)) {
        janet_panic("Skia render self-test allocation failed");
    }
    return janet_wrap_integer(stats.black_pixels);
}

static Janet cfun_render_hello(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 0);
    (void) argv;

    FBInkConfig cfg;
    std::memset(&cfg, 0, sizeof(cfg));
    cfg.is_quiet = true;
    cfg.is_flashing = true;
    cfg.ignore_alpha = true;

    const int fbfd = fbink_open();
    if (fbfd < 0) {
        janet_panicf("fbink_open failed: errno=%d (%s)", errno, std::strerror(errno));
    }

    int rv = fbink_init(fbfd, &cfg);
    if (rv < 0) {
        const int saved = errno;
        fbink_close(fbfd);
        janet_panicf("fbink_init failed: rv=%d errno=%d (%s)", rv, saved, std::strerror(saved));
    }

    FBInkState state;
    std::memset(&state, 0, sizeof(state));
    fbink_get_state(&cfg, &state);

    const uint32_t target_width = state.view_width != 0 ? state.view_width : state.screen_width;
    const uint32_t target_height = state.view_height != 0 ? state.view_height : state.screen_height;
    if (target_width == 0 || target_height == 0 || target_width > INT_MAX || target_height > INT_MAX) {
        fbink_close(fbfd);
        janet_panicf("unsupported framebuffer dimensions: %ux%u", target_width, target_height);
    }

    SkBitmap bitmap;
    if (!render_hello_bitmap(static_cast<int>(target_width), static_cast<int>(target_height), &bitmap, nullptr)) {
        fbink_close(fbfd);
        janet_panicf("Skia render allocation failed for framebuffer dimensions: %ux%u", target_width, target_height);
    }

    const void *pixels = bitmap.getPixels();
    const size_t byte_count = bitmap.computeByteSize();
    if (pixels == nullptr || byte_count == 0) {
        fbink_close(fbfd);
        janet_panic("Skia render produced an empty bitmap");
    }

    rv = fbink_print_raw_data(
        fbfd,
        static_cast<const unsigned char *>(pixels),
        static_cast<int>(target_width),
        static_cast<int>(target_height),
        byte_count,
        0,
        0,
        &cfg);
    if (rv < 0) {
        const int saved = errno;
        fbink_close(fbfd);
        janet_panicf("fbink_print_raw_data failed: rv=%d errno=%d (%s)", rv, saved, std::strerror(saved));
    }

    close_or_panic(fbfd);
    return janet_wrap_integer(rv);
}

static const JanetReg cfuns[] = {
    {
        "self-test", cfun_self_test,
        "(skia/self-test)\n\n"
        "Render the Hello Skia demo off-screen and return the count of black pixels."
    },
    {
        "render-hello", cfun_render_hello,
        "(skia/render-hello)\n\n"
        "Render a white full-screen Skia bitmap with black centered `Hello Skia!` text and present it via FBInk."
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    janet_cfuns(env, "skia", cfuns);
}
