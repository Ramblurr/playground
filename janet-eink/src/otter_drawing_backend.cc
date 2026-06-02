#include "otter_drawing_backend.hh"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <limits>

#include "core/SkCanvas.h"
#include "core/SkColor.h"
#include "core/SkImageInfo.h"
#include "core/SkPaint.h"
#include "core/SkPathBuilder.h"
#include "core/SkRect.h"

namespace otter {
namespace {

constexpr std::uint64_t kFnvOffset = 1469598103934665603ULL;
constexpr std::uint64_t kFnvPrime = 1099511628211ULL;

SkColor gray_color(std::uint8_t gray) {
    return SkColorSetARGB(255, gray, gray, gray);
}

SkPaint fill_paint(std::uint8_t gray) {
    SkPaint paint;
    paint.setAntiAlias(false);
    paint.setColor(gray_color(gray));
    paint.setStyle(SkPaint::kFill_Style);
    return paint;
}

bool positive(float value) {
    return std::isfinite(value) && value > 0.0f;
}

int clamp_dimension(float value) {
    if (!std::isfinite(value)) {
        return 0;
    }
    if (value > static_cast<float>(std::numeric_limits<int>::max())) {
        return std::numeric_limits<int>::max();
    }
    return static_cast<int>(std::lround(value));
}

}  // namespace

bool valid_dimensions(int width, int height) {
    if (width <= 0 || height <= 0) {
        return false;
    }
    const std::size_t row_bytes = static_cast<std::size_t>(width);
    const std::size_t rows = static_cast<std::size_t>(height);
    return rows <= std::numeric_limits<std::size_t>::max() / row_bytes;
}

bool GrayCanvas::reset(int width, int height) {
    if (!valid_dimensions(width, height)) {
        return false;
    }

    const SkImageInfo info = SkImageInfo::Make(
        width,
        height,
        kGray_8_SkColorType,
        kOpaque_SkAlphaType);
    const std::size_t row_bytes = static_cast<std::size_t>(width);

    bitmap_.reset();
    return bitmap_.tryAllocPixels(info, row_bytes);
}

void clear(GrayCanvas &canvas, std::uint8_t gray) {
    SkBitmap &bitmap = canvas.bitmap();
    const int width = bitmap.width();
    const int height = bitmap.height();
    for (int y = 0; y < height; ++y) {
        std::uint8_t *row = static_cast<std::uint8_t *>(bitmap.getAddr(0, y));
        std::memset(row, gray, static_cast<std::size_t>(width));
    }
}

bool draw_rect(GrayCanvas &canvas, float x, float y, float width, float height, std::uint8_t gray) {
    if (!positive(width) || !positive(height)) {
        return false;
    }
    SkCanvas sk(canvas.bitmap());
    sk.drawRect(SkRect::MakeXYWH(x, y, width, height), fill_paint(gray));
    return true;
}

bool draw_round_rect(GrayCanvas &canvas, float x, float y, float width, float height, float radius, std::uint8_t gray) {
    if (!positive(width) || !positive(height) || !std::isfinite(radius)) {
        return false;
    }
    const SkScalar r = std::max(0.0f, radius);
    SkCanvas sk(canvas.bitmap());
    sk.drawRoundRect(SkRect::MakeXYWH(x, y, width, height), r, r, fill_paint(gray));
    return true;
}

bool draw_triangle(
    GrayCanvas &canvas,
    float x1,
    float y1,
    float x2,
    float y2,
    float x3,
    float y3,
    std::uint8_t gray) {
    if (!std::isfinite(x1) || !std::isfinite(y1) ||
        !std::isfinite(x2) || !std::isfinite(y2) ||
        !std::isfinite(x3) || !std::isfinite(y3)) {
        return false;
    }

    SkPathBuilder builder;
    builder.moveTo(x1, y1);
    builder.lineTo(x2, y2);
    builder.lineTo(x3, y3);
    builder.close();

    SkCanvas sk(canvas.bitmap());
    sk.drawPath(builder.detach(), fill_paint(gray));
    return true;
}

bool draw_circle(GrayCanvas &canvas, float cx, float cy, float radius, std::uint8_t gray) {
    if (!std::isfinite(cx) || !std::isfinite(cy) || !positive(radius)) {
        return false;
    }
    SkCanvas sk(canvas.bitmap());
    sk.drawCircle(cx, cy, radius, fill_paint(gray));
    return true;
}

std::uint8_t sample_gray(const GrayCanvas &canvas, int x, int y) {
    const SkBitmap &bitmap = canvas.bitmap();
    if (x < 0 || y < 0 || x >= bitmap.width() || y >= bitmap.height()) {
        return 0;
    }
    const std::uint8_t *row = static_cast<const std::uint8_t *>(bitmap.getAddr(0, y));
    return row[x];
}

GrayStats compute_stats(const GrayCanvas &canvas) {
    const SkBitmap &bitmap = canvas.bitmap();
    GrayStats stats;
    stats.width = bitmap.width();
    stats.height = bitmap.height();
    stats.min_gray = 255;
    stats.max_gray = 0;
    stats.checksum = kFnvOffset;

    bool seen[256] = {false};
    for (int y = 0; y < stats.height; ++y) {
        const std::uint8_t *row = static_cast<const std::uint8_t *>(bitmap.getAddr(0, y));
        for (int x = 0; x < stats.width; ++x) {
            const std::uint8_t gray = row[x];
            stats.min_gray = std::min(stats.min_gray, static_cast<int>(gray));
            stats.max_gray = std::max(stats.max_gray, static_cast<int>(gray));
            if (!seen[gray]) {
                seen[gray] = true;
                ++stats.gray_shades;
            }
            if (gray != 255) {
                ++stats.non_white_pixels;
            }
            stats.checksum ^= gray;
            stats.checksum *= kFnvPrime;
        }
    }

    if (stats.width == 0 || stats.height == 0) {
        stats.min_gray = 0;
        stats.max_gray = 0;
        stats.checksum = 0;
    }
    return stats;
}

bool render_demo_scene(int width, int height, GrayCanvas *canvas, GrayStats *stats) {
    if (canvas == nullptr || !canvas->reset(width, height)) {
        return false;
    }

    clear(*canvas, 255);

    const float margin = std::max(24.0f, width * 0.035f);
    const float top = std::max(24.0f, height * 0.045f);
    const float stripe_height = std::max(48.0f, height * 0.085f);
    const float usable_width = std::max(1.0f, width - margin * 2.0f);
    const float stripe_width = usable_width / 8.0f;
    const std::uint8_t stripes[] = {0, 32, 64, 96, 128, 160, 192, 224};
    for (int i = 0; i < 8; ++i) {
        draw_rect(*canvas,
                  margin + stripe_width * static_cast<float>(i),
                  top,
                  stripe_width - 4.0f,
                  stripe_height,
                  stripes[i]);
    }

    const float body_top = top + stripe_height + margin;
    const float column = usable_width / 3.0f;
    draw_rect(*canvas,
              margin,
              body_top,
              column * 0.82f,
              height * 0.34f,
              48);
    draw_round_rect(*canvas,
                    margin + column,
                    body_top,
                    column * 0.82f,
                    height * 0.34f,
                    std::max(16.0f, height * 0.035f),
                    144);
    draw_circle(*canvas,
                margin + column * 2.48f,
                body_top + height * 0.17f,
                std::min(column * 0.36f, height * 0.17f),
                96);

    const float lower_top = body_top + height * 0.40f;
    draw_triangle(*canvas,
                  margin,
                  lower_top + height * 0.30f,
                  margin + usable_width * 0.24f,
                  lower_top,
                  margin + usable_width * 0.48f,
                  lower_top + height * 0.30f,
                  192);
    draw_triangle(*canvas,
                  margin + usable_width * 0.52f,
                  lower_top,
                  margin + usable_width,
                  lower_top + height * 0.02f,
                  margin + usable_width * 0.76f,
                  lower_top + height * 0.32f,
                  16);
    draw_round_rect(*canvas,
                    margin + usable_width * 0.30f,
                    lower_top + height * 0.14f,
                    usable_width * 0.40f,
                    height * 0.16f,
                    std::max(12.0f, height * 0.020f),
                    224);
    draw_circle(*canvas,
                margin + usable_width * 0.50f,
                lower_top + height * 0.22f,
                std::min(width * 0.055f, height * 0.075f),
                0);

    const int border = std::max(2, clamp_dimension(std::min(width, height) * 0.004f));
    draw_rect(*canvas, 0.0f, 0.0f, static_cast<float>(width), static_cast<float>(border), 0);
    draw_rect(*canvas, 0.0f, static_cast<float>(height - border), static_cast<float>(width), static_cast<float>(border), 0);
    draw_rect(*canvas, 0.0f, 0.0f, static_cast<float>(border), static_cast<float>(height), 0);
    draw_rect(*canvas, static_cast<float>(width - border), 0.0f, static_cast<float>(border), static_cast<float>(height), 0);

    if (stats != nullptr) {
        *stats = compute_stats(*canvas);
    }
    return true;
}

void gray8_to_rgba32(const GrayCanvas &canvas, std::vector<std::uint8_t> *rgba) {
    const int width = canvas.width();
    const int height = canvas.height();
    rgba->assign(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U, 0);

    for (int y = 0; y < height; ++y) {
        const std::uint8_t *src = static_cast<const std::uint8_t *>(canvas.bitmap().getAddr(0, y));
        std::uint8_t *dst = rgba->data() + static_cast<std::size_t>(y) * static_cast<std::size_t>(width) * 4U;
        for (int x = 0; x < width; ++x) {
            const std::uint8_t gray = src[x];
            dst[x * 4 + 0] = gray;
            dst[x * 4 + 1] = gray;
            dst[x * 4 + 2] = gray;
            dst[x * 4 + 3] = 255;
        }
    }
}

}  // namespace otter
