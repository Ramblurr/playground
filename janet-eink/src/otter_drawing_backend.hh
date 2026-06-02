#ifndef OTTER_DRAWING_BACKEND_HH
#define OTTER_DRAWING_BACKEND_HH

#include <cstdint>
#include <vector>

#include "core/SkBitmap.h"

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

class GrayCanvas {
public:
    GrayCanvas() = default;

    bool reset(int width, int height);

    int width() const { return bitmap_.width(); }
    int height() const { return bitmap_.height(); }
    std::size_t row_bytes() const { return bitmap_.rowBytes(); }

    SkBitmap &bitmap() { return bitmap_; }
    const SkBitmap &bitmap() const { return bitmap_; }

private:
    SkBitmap bitmap_;
};

bool valid_dimensions(int width, int height);
void clear(GrayCanvas &canvas, std::uint8_t gray);
bool draw_rect(GrayCanvas &canvas, float x, float y, float width, float height, std::uint8_t gray);
bool draw_round_rect(GrayCanvas &canvas, float x, float y, float width, float height, float radius, std::uint8_t gray);
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
std::uint8_t sample_gray(const GrayCanvas &canvas, int x, int y);
GrayStats compute_stats(const GrayCanvas &canvas);
bool render_demo_scene(int width, int height, GrayCanvas *canvas, GrayStats *stats);
void gray8_to_rgba32(const GrayCanvas &canvas, std::vector<std::uint8_t> *rgba);

}  // namespace otter

#endif  // OTTER_DRAWING_BACKEND_HH
