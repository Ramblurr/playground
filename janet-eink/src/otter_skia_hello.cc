#include "otter_skia_hello.hh"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>

#include "core/SkCanvas.h"
#include "core/SkColor.h"
#include "core/SkImageInfo.h"
#include "core/SkPaint.h"
#include "core/SkRect.h"

namespace otter {
namespace {

constexpr int kGlyphWidth = 5;
constexpr int kGlyphHeight = 7;
constexpr int kGlyphGap = 1;

struct Glyph {
    char ch;
    const char *rows[kGlyphHeight];
};

constexpr Glyph kGlyphs[] = {
    {' ', {"00000", "00000", "00000", "00000", "00000", "00000", "00000"}},
    {'!', {"00100", "00100", "00100", "00100", "00100", "00000", "00100"}},
    {'A', {"01110", "10001", "10001", "11111", "10001", "10001", "10001"}},
    {'E', {"11111", "10000", "10000", "11110", "10000", "10000", "11111"}},
    {'H', {"10001", "10001", "10001", "11111", "10001", "10001", "10001"}},
    {'I', {"11111", "00100", "00100", "00100", "00100", "00100", "11111"}},
    {'K', {"10001", "10010", "10100", "11000", "10100", "10010", "10001"}},
    {'L', {"10000", "10000", "10000", "10000", "10000", "10000", "11111"}},
    {'O', {"01110", "10001", "10001", "10001", "10001", "10001", "01110"}},
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

}  // namespace

bool render_hello_bitmap(int width, int height, const char *text, SkBitmap *bitmap, RenderStats *stats) {
    if (width <= 0 || height <= 0 || text == nullptr || bitmap == nullptr) {
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

    const int columns = text_columns(text);
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
    draw_block_text(canvas, text, text_x, text_y, scale, black_fill);

    if (stats != nullptr) {
        stats->black_pixels = count_black_pixels(*bitmap);
    }
    return true;
}

}  // namespace otter
