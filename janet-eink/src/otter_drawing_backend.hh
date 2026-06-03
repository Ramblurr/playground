#ifndef OTTER_DRAWING_BACKEND_HH
#define OTTER_DRAWING_BACKEND_HH

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "core/SkBitmap.h"

#include "core/SkFontStyle.h"
#include "core/SkRefCnt.h"
#include "core/SkTextBlob.h"
#include "modules/skshaper/include/SkShaper.h"
class SkCanvas;

namespace otter {

constexpr int kKoboScreenWidth = 1264;
constexpr int kKoboScreenHeight = 1680;

enum class PixelFormat {
    Gray8,
    Gray8a,
    Rgba32,
};

struct CanvasStats {
    int width = 0;
    int height = 0;
    PixelFormat pixel_format = PixelFormat::Gray8;
    int min_gray = 255;
    int max_gray = 0;
    int gray_shades = 0;
    int non_white_pixels = 0;
    std::uint64_t checksum = 0;
};

struct RgbaPixel {
    std::uint8_t r = 0;
    std::uint8_t g = 0;
    std::uint8_t b = 0;
    std::uint8_t a = 255;
};

enum class PaintStyle {
    Fill,
    Stroke,
};

enum class PaintCap {
    Butt,
    Round,
    Square,
};

enum class PaintJoin {
    Miter,
    Round,
    Bevel,
};

struct NormalizedPaint {
    PaintStyle style = PaintStyle::Fill;
    float r = 0.0f;
    float g = 0.0f;
    float b = 0.0f;
    float a = 1.0f;
    float stroke_width = 1.0f;
    PaintCap cap = PaintCap::Butt;
    PaintJoin join = PaintJoin::Miter;
    float miter = 4.0f;
    bool anti_alias = true;
    bool skia_dither = false;
};

struct FontOptions {
    std::string family;
    float size = 16.0f;
    int weight = 400;
    int width = SkFontStyle::kNormal_Width;
    int slant = 0;
};

struct TextLineMetrics {
    float width = 0.0f;
    float height = 0.0f;
};

class TextLine {
public:
    std::string utf8;
    FontOptions font_options;
    std::string features_string;
    std::vector<SkShaper::Feature> features;
    sk_sp<SkTextBlob> blob;
    TextLineMetrics metrics;
};

struct TextState;

class RasterCanvas {
public:
    RasterCanvas();
    ~RasterCanvas();
    RasterCanvas(const RasterCanvas &) = delete;
    RasterCanvas &operator=(const RasterCanvas &) = delete;

    bool reset(int width, int height, PixelFormat pixel_format = PixelFormat::Gray8, const char *font_dir = nullptr, const char *default_family = nullptr);

    PixelFormat pixel_format() const { return pixel_format_; }
    int width() const { return bitmap_.width(); }
    int height() const { return bitmap_.height(); }
    std::size_t row_bytes() const { return bitmap_.rowBytes(); }

    SkBitmap &bitmap() { return bitmap_; }
    const SkBitmap &bitmap() const { return bitmap_; }
    SkCanvas &sk_canvas();
    TextState *text_state();

private:
    PixelFormat pixel_format_ = PixelFormat::Gray8;
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
    bool reset(int width, int height, PixelFormat pixel_format, const std::vector<std::uint8_t> &pixels);
    PixelFormat pixel_format() const { return pixel_format_; }
    int width() const { return width_; }
    int height() const { return height_; }
    const SkBitmap &bitmap() const { return bitmap_; }

private:
    PixelFormat pixel_format_ = PixelFormat::Rgba32;
    int width_ = 0;
    int height_ = 0;
    SkBitmap bitmap_;
};

bool valid_dimensions(int width, int height, PixelFormat pixel_format = PixelFormat::Gray8);
const char *pixel_format_name(PixelFormat pixel_format);
void clear(RasterCanvas &canvas, const NormalizedPaint &paint);
bool draw_rect(RasterCanvas &canvas, float x, float y, float width, float height, const NormalizedPaint &paint);
bool draw_rounded_rect(RasterCanvas &canvas, float x, float y, float width, float height, float radius, const NormalizedPaint &paint);
bool draw_rrect(RasterCanvas &canvas, float x, float y, float width, float height, const std::vector<float> &radii, const NormalizedPaint &paint);
bool draw_triangle(
    RasterCanvas &canvas,
    float x1,
    float y1,
    float x2,
    float y2,
    float x3,
    float y3,
    const NormalizedPaint &paint);
bool draw_circle(RasterCanvas &canvas, float cx, float cy, float radius, const NormalizedPaint &paint);
bool save(RasterCanvas &canvas);
bool restore(RasterCanvas &canvas);
bool translate(RasterCanvas &canvas, float x, float y);
bool scale(RasterCanvas &canvas, float sx, float sy);
bool clip_rect(RasterCanvas &canvas, float x, float y, float width, float height);
bool draw_line(RasterCanvas &canvas, float x1, float y1, float x2, float y2, const NormalizedPaint &paint);
bool draw_path(RasterCanvas &canvas, const std::vector<float> &coords, bool closed, const NormalizedPaint &paint);
bool shape_text(RasterCanvas &canvas, const std::string &utf8, const FontOptions &font_options, const std::string &features_string, TextLine *line, std::string *error_message);
bool draw_text_line(RasterCanvas &canvas, const TextLine &line, float x, float y, const NormalizedPaint &paint);
bool draw_image(RasterCanvas &canvas, const RasterImage &image, float src_x, float src_y, float src_width, float src_height, float dst_x, float dst_y, float dst_width, float dst_height, float alpha);
bool invert_rect(RasterCanvas &canvas, float x, float y, float width, float height);
std::uint8_t sample_gray(const RasterCanvas &canvas, int x, int y);
RgbaPixel sample_rgba(const RasterCanvas &canvas, int x, int y);
CanvasStats compute_stats(const RasterCanvas &canvas);
void canvas_to_rgba32(const RasterCanvas &canvas, std::vector<std::uint8_t> *rgba);

}  // namespace otter

#endif  // OTTER_DRAWING_BACKEND_HH
