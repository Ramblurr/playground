#ifndef OTTER_DRAWING_BACKEND_HH
#define OTTER_DRAWING_BACKEND_HH

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "core/SkBitmap.h"

class SkCanvas;

namespace otter {

constexpr int kKoboScreenWidth = 1680;
constexpr int kKoboScreenHeight = 1264;

struct GrayStats {
    int width = 0;
    int height = 0;
    int min_gray = 255;
    int max_gray = 0;
    int gray_shades = 0;
    int non_white_pixels = 0;
    std::uint64_t checksum = 0;
};

struct TextMetrics {
    float width = 0.0f;
    float height = 0.0f;
    float ascent = 0.0f;
    float descent = 0.0f;
    float baseline = 0.0f;
};

struct TextState;

class GrayCanvas {
public:
    GrayCanvas();
    ~GrayCanvas();
    GrayCanvas(const GrayCanvas &) = delete;
    GrayCanvas &operator=(const GrayCanvas &) = delete;

    bool reset(int width, int height, const char *font_dir = nullptr, const char *default_family = nullptr);

    int width() const { return bitmap_.width(); }
    int height() const { return bitmap_.height(); }
    std::size_t row_bytes() const { return bitmap_.rowBytes(); }

    SkBitmap &bitmap() { return bitmap_; }
    const SkBitmap &bitmap() const { return bitmap_; }
    SkCanvas &sk_canvas();
    TextState *text_state();

private:
    SkBitmap bitmap_;
    std::unique_ptr<SkCanvas> canvas_;
    std::unique_ptr<TextState> text_;
};

class RasterImage {
public:
    RasterImage();
    ~RasterImage();
    RasterImage(const RasterImage &) = delete;
    RasterImage &operator=(const RasterImage &) = delete;

    bool load_png(const char *path);
    int width() const { return bitmap_.width(); }
    int height() const { return bitmap_.height(); }
    const SkBitmap &bitmap() const { return bitmap_; }

private:
    SkBitmap bitmap_;
};

bool valid_dimensions(int width, int height);
void clear(GrayCanvas &canvas, std::uint8_t gray);
bool draw_rect(GrayCanvas &canvas, float x, float y, float width, float height, std::uint8_t gray);
bool draw_rounded_rect(GrayCanvas &canvas, float x, float y, float width, float height, float radius, std::uint8_t gray);
bool draw_triangle(
    GrayCanvas &canvas,
    float x1,
    float y1,
    float x2,
    float y2,
    float x3,
    float y3,
    std::uint8_t gray);
bool draw_circle(GrayCanvas &canvas, float cx, float cy, float radius, std::uint8_t gray);
bool save(GrayCanvas &canvas);
bool restore(GrayCanvas &canvas);
bool translate(GrayCanvas &canvas, float x, float y);
bool scale(GrayCanvas &canvas, float sx, float sy);
bool clip_rect(GrayCanvas &canvas, float x, float y, float width, float height);
bool draw_line(GrayCanvas &canvas, float x1, float y1, float x2, float y2, std::uint8_t gray, float stroke_width);
bool draw_path(GrayCanvas &canvas, const std::vector<float> &coords, bool closed, std::uint8_t gray);
bool measure_text(GrayCanvas &canvas, const std::string &utf8, const std::string &family, float size, int weight, TextMetrics *metrics);
bool draw_text(GrayCanvas &canvas, const std::string &utf8, float x, float y, const std::string &family, float size, int weight, std::uint8_t gray);
bool draw_image(GrayCanvas &canvas, const RasterImage &image, float src_x, float src_y, float src_width, float src_height, float dst_x, float dst_y, float dst_width, float dst_height, float alpha);
std::uint8_t sample_gray(const GrayCanvas &canvas, int x, int y);
GrayStats compute_stats(const GrayCanvas &canvas);
void gray8_to_rgba32(const GrayCanvas &canvas, std::vector<std::uint8_t> *rgba);

}  // namespace otter

#endif  // OTTER_DRAWING_BACKEND_HH
