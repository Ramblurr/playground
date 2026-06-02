#include "otter_drawing_backend.hh"

#include <algorithm>
#include <cmath>
#include <cctype>
#include <cstddef>
#include <cstring>
#include <filesystem>
#include <limits>
#include <memory>
#include <string>

#include "codec/SkCodec.h"
#include "core/SkCanvas.h"
#include "core/SkColor.h"
#include "core/SkImageInfo.h"
#include "core/SkPaint.h"
#include "core/SkPathBuilder.h"
#include "core/SkData.h"
#include "core/SkImage.h"
#include "core/SkRect.h"
#include "core/SkFont.h"
#include "core/SkFontMgr.h"
#include "core/SkFontMetrics.h"
#include "core/SkFontStyle.h"
#include "core/SkString.h"
#include "core/SkTypeface.h"
#include "ports/SkFontMgr_directory.h"

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

SkPaint stroke_paint(std::uint8_t gray, float stroke_width) {
    SkPaint paint;
    paint.setAntiAlias(false);
    paint.setColor(gray_color(gray));
    paint.setStyle(SkPaint::kStroke_Style);
    paint.setStrokeWidth(stroke_width);
    return paint;
}

bool positive(float value) {
    return std::isfinite(value) && value > 0.0f;
}

bool finite_pair(float x, float y) {
    return std::isfinite(x) && std::isfinite(y);
}

bool has_supported_font_extension(const std::filesystem::path &path) {
    std::string extension = path.extension().string();
    std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    return extension == ".ttf" || extension == ".otf" || extension == ".ttc";
}

bool usable_font_dir(const char *font_dir) {
    if (font_dir == nullptr || font_dir[0] == '\0') {
        return false;
    }
    std::error_code ec;
    std::filesystem::path dir(font_dir);
    if (!std::filesystem::is_directory(dir, ec) || ec) {
        return false;
    }
    std::filesystem::directory_iterator it(dir, std::filesystem::directory_options::skip_permission_denied, ec);
    if (ec) {
        return false;
    }
    for (std::filesystem::directory_iterator end; it != end; it.increment(ec)) {
        if (ec) {
            ec.clear();
            continue;
        }
        if (std::filesystem::is_regular_file(it->path(), ec) && !ec && has_supported_font_extension(it->path())) {
            return true;
        }
        ec.clear();
    }
    return false;
}

SkFontStyle::Slant decode_slant(int slant) {
    switch (slant) {
        case 1: return SkFontStyle::kItalic_Slant;
        case 2: return SkFontStyle::kOblique_Slant;
        case 0:
        default: return SkFontStyle::kUpright_Slant;
    }
}

int normalize_weight(int weight) {
    if (weight <= 0) {
        return SkFontStyle::kNormal_Weight;
    }
    return std::clamp(weight,
                      static_cast<int>(SkFontStyle::kInvisible_Weight),
                      static_cast<int>(SkFontStyle::kExtraBlack_Weight));
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

struct TextState {
    sk_sp<SkFontMgr> font_mgr;
    std::string font_dir;
    std::string default_family;
};

GrayCanvas::GrayCanvas() = default;

GrayCanvas::~GrayCanvas() = default;

bool GrayCanvas::reset(int width, int height, const char *font_dir, const char *default_family) {
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
    canvas_.reset();
    text_.reset();
    if (!bitmap_.tryAllocPixels(info, row_bytes)) {
        return false;
    }
    canvas_ = std::make_unique<SkCanvas>(bitmap_);

    if (font_dir != nullptr && font_dir[0] != '\0') {
        if (!usable_font_dir(font_dir)) {
            return false;
        }
        auto text = std::make_unique<TextState>();
        text->font_dir = font_dir;
        text->font_mgr = SkFontMgr_New_Custom_Directory(text->font_dir.c_str());
        if (!text->font_mgr || text->font_mgr->countFamilies() <= 0) {
            return false;
        }
        if (default_family != nullptr && default_family[0] != '\0') {
            text->default_family = default_family;
        } else {
            SkString family_name;
            text->font_mgr->getFamilyName(0, &family_name);
            text->default_family = family_name.c_str();
        }
        text_ = std::move(text);
    }

    return true;
}

SkCanvas &GrayCanvas::sk_canvas() {
    return *canvas_;
}

TextState *GrayCanvas::text_state() {
    return text_.get();
}

RasterImage::RasterImage() = default;

RasterImage::~RasterImage() = default;

bool RasterImage::load_png(const char *path) {
    if (path == nullptr || path[0] == '\0') {
        return false;
    }

    sk_sp<SkData> data = SkData::MakeFromFileName(path);
    if (!data) {
        return false;
    }

    std::unique_ptr<SkCodec> codec = SkCodec::MakeFromData(std::move(data));
    if (!codec) {
        return false;
    }

    const SkImageInfo info = codec->getInfo().makeColorType(kN32_SkColorType).makeAlphaType(kPremul_SkAlphaType);
    SkBitmap bitmap;
    if (!bitmap.tryAllocPixels(info)) {
        return false;
    }

    const SkCodec::Result result = codec->getPixels(info, bitmap.getPixels(), bitmap.rowBytes());
    if (result != SkCodec::kSuccess) {
        return false;
    }

    bitmap.setImmutable();
    bitmap_ = bitmap;
    return true;
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
    canvas.sk_canvas().drawRect(SkRect::MakeXYWH(x, y, width, height), fill_paint(gray));
    return true;
}

bool draw_rounded_rect(GrayCanvas &canvas, float x, float y, float width, float height, float radius, std::uint8_t gray) {
    if (!positive(width) || !positive(height) || !std::isfinite(radius)) {
        return false;
    }
    const SkScalar r = std::max(0.0f, radius);
    canvas.sk_canvas().drawRoundRect(SkRect::MakeXYWH(x, y, width, height), r, r, fill_paint(gray));
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
    if (!finite_pair(x1, y1) || !finite_pair(x2, y2) || !finite_pair(x3, y3)) {
        return false;
    }

    SkPathBuilder builder;
    builder.moveTo(x1, y1);
    builder.lineTo(x2, y2);
    builder.lineTo(x3, y3);
    builder.close();

    canvas.sk_canvas().drawPath(builder.detach(), fill_paint(gray));
    return true;
}

bool draw_circle(GrayCanvas &canvas, float cx, float cy, float radius, std::uint8_t gray) {
    if (!std::isfinite(cx) || !std::isfinite(cy) || !positive(radius)) {
        return false;
    }
    canvas.sk_canvas().drawCircle(cx, cy, radius, fill_paint(gray));
    return true;
}

bool save(GrayCanvas &canvas) {
    canvas.sk_canvas().save();
    return true;
}

bool restore(GrayCanvas &canvas) {
    if (canvas.sk_canvas().getSaveCount() <= 1) {
        return false;
    }
    canvas.sk_canvas().restore();
    return true;
}

bool translate(GrayCanvas &canvas, float x, float y) {
    if (!finite_pair(x, y)) {
        return false;
    }
    canvas.sk_canvas().translate(x, y);
    return true;
}

bool scale(GrayCanvas &canvas, float sx, float sy) {
    if (!finite_pair(sx, sy)) {
        return false;
    }
    canvas.sk_canvas().scale(sx, sy);
    return true;
}

bool clip_rect(GrayCanvas &canvas, float x, float y, float width, float height) {
    if (!finite_pair(x, y) || !positive(width) || !positive(height)) {
        return false;
    }
    canvas.sk_canvas().clipRect(SkRect::MakeXYWH(x, y, width, height));
    return true;
}

bool draw_line(GrayCanvas &canvas, float x1, float y1, float x2, float y2, std::uint8_t gray, float stroke_width) {
    if (!finite_pair(x1, y1) || !finite_pair(x2, y2) || !positive(stroke_width)) {
        return false;
    }
    canvas.sk_canvas().drawLine(x1, y1, x2, y2, stroke_paint(gray, stroke_width));
    return true;
}

bool draw_path(GrayCanvas &canvas, const std::vector<float> &coords, bool closed, std::uint8_t gray) {
    if (coords.size() < 4 || coords.size() % 2 != 0) {
        return false;
    }

    SkPathBuilder builder;
    for (std::size_t i = 0; i < coords.size(); i += 2) {
        const float x = coords[i];
        const float y = coords[i + 1];
        if (!finite_pair(x, y)) {
            return false;
        }
        if (i == 0) {
            builder.moveTo(x, y);
        } else {
            builder.lineTo(x, y);
        }
    }
    if (closed) {
        builder.close();
    }

    canvas.sk_canvas().drawPath(builder.detach(), fill_paint(gray));
    return true;
}

bool draw_image(GrayCanvas &canvas, const RasterImage &image, float src_x, float src_y, float src_width, float src_height, float dst_x, float dst_y, float dst_width, float dst_height, float alpha) {
    if (!positive(src_width) || !positive(src_height) || !positive(dst_width) || !positive(dst_height) || !finite_pair(src_x, src_y) || !finite_pair(dst_x, dst_y) || !std::isfinite(alpha)) {
        return false;
    }
    if (image.width() <= 0 || image.height() <= 0) {
        return false;
    }
    if (src_x < 0.0f || src_y < 0.0f || src_x + src_width > static_cast<float>(image.width()) || src_y + src_height > static_cast<float>(image.height())) {
        return false;
    }

    sk_sp<SkImage> sk_image = image.bitmap().asImage();
    if (!sk_image) {
        return false;
    }

    SkPaint paint;
    paint.setAntiAlias(false);
    paint.setAlphaf(std::clamp(alpha, 0.0f, 1.0f));
    const SkRect src = SkRect::MakeXYWH(src_x, src_y, src_width, src_height);
    const SkRect dst = SkRect::MakeXYWH(dst_x, dst_y, dst_width, dst_height);
    canvas.sk_canvas().drawImageRect(sk_image, src, dst, SkSamplingOptions(), &paint, SkCanvas::kStrict_SrcRectConstraint);
    return true;
}

sk_sp<SkTypeface> select_typeface(GrayCanvas &canvas, const std::string &family, int weight) {
    TextState *text = canvas.text_state();
    if (text == nullptr || !text->font_mgr) {
        return nullptr;
    }
    const std::string selected_family = family.empty() ? text->default_family : family;
    sk_sp<SkTypeface> typeface(text->font_mgr->matchFamilyStyle(
        selected_family.c_str(),
        SkFontStyle(normalize_weight(weight), SkFontStyle::kNormal_Width, decode_slant(0))));
    if (!typeface && !text->default_family.empty()) {
        typeface = text->font_mgr->matchFamilyStyle(
            text->default_family.c_str(),
            SkFontStyle(normalize_weight(weight), SkFontStyle::kNormal_Width, decode_slant(0)));
    }
    return typeface;
}

SkFont make_font(sk_sp<SkTypeface> typeface, float size) {
    SkFont font(std::move(typeface), size);
    font.setEdging(SkFont::Edging::kAntiAlias);
    return font;
}

bool measure_text(GrayCanvas &canvas, const std::string &utf8, const std::string &family, float size, int weight, TextMetrics *metrics) {
    if (metrics == nullptr || !positive(size)) {
        return false;
    }
    sk_sp<SkTypeface> typeface = select_typeface(canvas, family, weight);
    if (!typeface) {
        return false;
    }
    SkFont font = make_font(typeface, size);
    SkRect bounds;
    metrics->width = font.measureText(utf8.data(), utf8.size(), SkTextEncoding::kUTF8, &bounds);
    SkFontMetrics font_metrics;
    font.getMetrics(&font_metrics);
    metrics->ascent = std::abs(font_metrics.fAscent);
    metrics->descent = std::max(0.0f, font_metrics.fDescent);
    metrics->height = metrics->ascent + metrics->descent + std::max(0.0f, font_metrics.fLeading);
    metrics->baseline = metrics->ascent;
    return true;
}

bool draw_text(GrayCanvas &canvas, const std::string &utf8, float x, float y, const std::string &family, float size, int weight, std::uint8_t gray) {
    if (!finite_pair(x, y) || !positive(size)) {
        return false;
    }
    sk_sp<SkTypeface> typeface = select_typeface(canvas, family, weight);
    if (!typeface) {
        return false;
    }
    SkFont font = make_font(typeface, size);
    SkFontMetrics font_metrics;
    font.getMetrics(&font_metrics);
    SkPaint paint = fill_paint(gray);
    paint.setAntiAlias(true);
    canvas.sk_canvas().drawSimpleText(
        utf8.data(),
        utf8.size(),
        SkTextEncoding::kUTF8,
        x,
        y + std::abs(font_metrics.fAscent),
        font,
        paint);
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
