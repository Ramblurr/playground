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
#include <sstream>

#include "codec/SkCodec.h"
#include "core/SkCanvas.h"
#include "core/SkColor.h"
#include "core/SkImageInfo.h"
#include "core/SkPaint.h"
#include "core/SkPathBuilder.h"
#include "core/SkData.h"
#include "core/SkImage.h"
#include "core/SkRect.h"
#include "core/SkRRect.h"
#include "core/SkFont.h"
#include "core/SkFontMgr.h"
#include "core/SkFontMetrics.h"
#include "core/SkFontStyle.h"
#include "core/SkString.h"
#include "core/SkTypeface.h"
#include "ports/SkFontMgr_directory.h"
#include "modules/skshaper/include/SkShaper_harfbuzz.h"

namespace otter {
namespace {

constexpr std::uint64_t kFnvOffset = 1469598103934665603ULL;
constexpr std::uint64_t kFnvPrime = 1099511628211ULL;

std::uint8_t unit_to_byte(float value) {
    if (!std::isfinite(value)) {
        return 0;
    }
    return static_cast<std::uint8_t>(std::clamp(std::lround(value * 255.0f), 0L, 255L));
}

std::uint8_t luminance_byte(const NormalizedPaint &paint) {
    const float gray = (0.299f * paint.r) + (0.587f * paint.g) + (0.114f * paint.b);
    return unit_to_byte(gray);
}

SkColor gray_color(const NormalizedPaint &paint) {
    const std::uint8_t gray = luminance_byte(paint);
    return SkColorSetARGB(unit_to_byte(paint.a), gray, gray, gray);
}

SkColor rgba_color(const NormalizedPaint &paint) {
    return SkColorSetARGB(unit_to_byte(paint.a), unit_to_byte(paint.r), unit_to_byte(paint.g), unit_to_byte(paint.b));
}

SkPaint skia_paint(PixelFormat pixel_format, const NormalizedPaint &normalized) {
    SkPaint paint;
    paint.setAntiAlias(normalized.anti_alias);
    paint.setDither(normalized.skia_dither);
    paint.setColor(pixel_format == PixelFormat::Gray8 ? gray_color(normalized) : rgba_color(normalized));
    paint.setStyle(normalized.style == PaintStyle::Stroke ? SkPaint::kStroke_Style : SkPaint::kFill_Style);
    paint.setStrokeWidth(normalized.stroke_width);
    switch (normalized.cap) {
        case PaintCap::Round: paint.setStrokeCap(SkPaint::kRound_Cap); break;
        case PaintCap::Square: paint.setStrokeCap(SkPaint::kSquare_Cap); break;
        case PaintCap::Butt:
        default: paint.setStrokeCap(SkPaint::kButt_Cap); break;
    }
    switch (normalized.join) {
        case PaintJoin::Round: paint.setStrokeJoin(SkPaint::kRound_Join); break;
        case PaintJoin::Bevel: paint.setStrokeJoin(SkPaint::kBevel_Join); break;
        case PaintJoin::Miter:
        default: paint.setStrokeJoin(SkPaint::kMiter_Join); break;
    }
    paint.setStrokeMiter(normalized.miter);
    return paint;
}

bool positive(float value) {
    return std::isfinite(value) && value > 0.0f;
}

bool finite_pair(float x, float y) {
    return std::isfinite(x) && std::isfinite(y);
}

constexpr std::uint8_t kBayer8Thresholds[64] = {
    1, 49, 13, 61, 4, 52, 16, 64,
    33, 17, 45, 29, 36, 20, 48, 32,
    9, 57, 5, 53, 12, 60, 8, 56,
    41, 25, 37, 21, 44, 28, 40, 24,
    3, 51, 15, 63, 2, 50, 14, 62,
    35, 19, 47, 31, 34, 18, 46, 30,
    11, 59, 7, 55, 10, 58, 6, 54,
    43, 27, 39, 23, 42, 26, 38, 22,
};

std::uint32_t div_255(std::uint32_t value) {
    const std::uint32_t rounded = value + 128U;
    return ((rounded >> 8U) + rounded) >> 8U;
}

std::uint8_t quantized_gray(std::uint8_t gray, const GrayConversionOptions &options, int x, int y) {
    if (options.quantize_gray_levels <= 1) {
        return gray;
    }

    const int levels = std::clamp(options.quantize_gray_levels, 2, 256);
    int index = 0;
    if (options.dither == DitherMode::Ordered) {
        std::uint32_t threshold = div_255(static_cast<std::uint32_t>(gray) * ((((static_cast<std::uint32_t>(levels) - 1U) << 6U) + 1U)));
        const std::uint32_t base = threshold >> 6U;
        threshold = threshold - (base << 6U);
        const std::uint32_t map = kBayer8Thresholds[(static_cast<unsigned int>(x) & 7U) + 8U * (static_cast<unsigned int>(y) & 7U)];
        index = static_cast<int>(base + (threshold >= map ? 1U : 0U));
    } else {
        const float scaled = (static_cast<float>(gray) * static_cast<float>(levels - 1)) / 255.0f;
        index = static_cast<int>(std::lround(scaled));
    }
    index = std::clamp(index, 0, levels - 1);
    return static_cast<std::uint8_t>(std::clamp(std::lround((static_cast<float>(index) * 255.0f) / static_cast<float>(levels - 1)), 0L, 255L));
}

void write_gray_pixel(RasterCanvas &canvas, int x, int y, std::uint8_t gray) {
    SkBitmap &bitmap = canvas.bitmap();
    if (canvas.pixel_format() == PixelFormat::Gray8) {
        auto *row = static_cast<std::uint8_t *>(bitmap.getAddr(0, y));
        row[x] = gray;
        return;
    }

    const SkColor existing = bitmap.getColor(x, y);
    const SkColor color = SkColorSetARGB(SkColorGetA(existing), gray, gray, gray);
    bitmap.erase(color, SkIRect::MakeXYWH(x, y, 1, 1));
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

int normalize_width(int width) {
    if (width <= 0) {
        return SkFontStyle::kNormal_Width;
    }
    return std::clamp(width,
                      static_cast<int>(SkFontStyle::kUltraCondensed_Width),
                      static_cast<int>(SkFontStyle::kUltraExpanded_Width));
}

SkFontStyle font_style_from_options(const FontOptions &options) {
    return SkFontStyle(normalize_weight(options.weight), normalize_width(options.width), decode_slant(options.slant));
}

bool feature_tag_char(char ch) {
    return (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9');
}

bool parse_unsigned_size(const std::string &token, std::size_t begin, std::size_t end, std::size_t *value) {
    if (value == nullptr || begin >= end) {
        return false;
    }
    std::size_t out = 0;
    for (std::size_t i = begin; i < end; ++i) {
        const char ch = token[i];
        if (ch < '0' || ch > '9') {
            return false;
        }
        const std::size_t digit = static_cast<std::size_t>(ch - '0');
        if (out > (std::numeric_limits<std::size_t>::max() - digit) / 10U) {
            return false;
        }
        out = out * 10U + digit;
    }
    *value = out;
    return true;
}

bool parse_unsigned_u32(const std::string &token, std::size_t begin, std::size_t end, std::uint32_t *value) {
    std::size_t parsed = 0;
    if (!parse_unsigned_size(token, begin, end, &parsed) || parsed > std::numeric_limits<std::uint32_t>::max()) {
        return false;
    }
    *value = static_cast<std::uint32_t>(parsed);
    return true;
}

void set_feature_error(const std::string &token, std::string *error_message) {
    if (error_message != nullptr) {
        *error_message = "invalid font feature \"" + token + "\"; expected Skija syntax like tnum, +cv09, -dlig, wdth=100, or tnum[0:3]";
    }
}

bool parse_feature_token(const std::string &token, SkShaper::Feature *feature, std::string *error_message) {
    if (feature == nullptr || token.empty()) {
        set_feature_error(token, error_message);
        return false;
    }

    std::size_t pos = 0;
    char sign = '\0';
    if (token[pos] == '+' || token[pos] == '-') {
        sign = token[pos];
        ++pos;
    }

    if (pos + 4U > token.size()) {
        set_feature_error(token, error_message);
        return false;
    }
    const std::size_t tag_begin = pos;
    for (std::size_t i = 0; i < 4U; ++i) {
        if (!feature_tag_char(token[tag_begin + i])) {
            set_feature_error(token, error_message);
            return false;
        }
    }
    const SkFourByteTag tag = SkSetFourByteTag(
        token[tag_begin], token[tag_begin + 1U], token[tag_begin + 2U], token[tag_begin + 3U]);
    pos += 4U;

    std::size_t start = 0;
    std::size_t end = std::numeric_limits<std::size_t>::max();
    if (pos < token.size() && token[pos] == '[') {
        ++pos;
        const std::size_t start_begin = pos;
        while (pos < token.size() && token[pos] != ':' && token[pos] != ']') {
            ++pos;
        }
        if (pos >= token.size() || token[pos] != ':') {
            set_feature_error(token, error_message);
            return false;
        }
        if (pos > start_begin && !parse_unsigned_size(token, start_begin, pos, &start)) {
            set_feature_error(token, error_message);
            return false;
        }
        ++pos;
        const std::size_t end_begin = pos;
        while (pos < token.size() && token[pos] != ']') {
            ++pos;
        }
        if (pos >= token.size() || token[pos] != ']') {
            set_feature_error(token, error_message);
            return false;
        }
        if (pos > end_begin && !parse_unsigned_size(token, end_begin, pos, &end)) {
            set_feature_error(token, error_message);
            return false;
        }
        ++pos;
    }

    std::uint32_t value = sign == '-' ? 0U : 1U;
    if (pos < token.size() && token[pos] == '=') {
        ++pos;
        const std::size_t value_begin = pos;
        if (value_begin >= token.size() || !parse_unsigned_u32(token, value_begin, token.size(), &value)) {
            set_feature_error(token, error_message);
            return false;
        }
        pos = token.size();
    }

    if (pos != token.size()) {
        set_feature_error(token, error_message);
        return false;
    }

    feature->tag = tag;
    feature->value = value;
    feature->start = start;
    feature->end = end;
    return true;
}

bool parse_features(const std::string &features_string, std::vector<SkShaper::Feature> *features, std::string *error_message) {
    if (features == nullptr) {
        return false;
    }
    features->clear();
    if (features_string.empty()) {
        return true;
    }

    std::istringstream input(features_string);
    std::string token;
    while (input >> token) {
        SkShaper::Feature feature;
        if (!parse_feature_token(token, &feature, error_message)) {
            return false;
        }
        features->push_back(feature);
    }
    return true;
}

class TextLineRunHandler final : public SkShaper::RunHandler {
public:
    explicit TextLineRunHandler(const char *utf8_text) : utf8_text_(utf8_text) {}

    sk_sp<SkTextBlob> make_blob() { return builder_.make(); }
    float advance_width() const { return advance_width_; }

    void beginLine() override {
        current_position_ = SkPoint::Make(0.0f, 0.0f);
        advance_width_ = 0.0f;
    }

    void runInfo(const RunInfo&) override {}
    void commitRunInfo() override {}

    Buffer runBuffer(const RunInfo &info) override {
        const int glyph_count = info.glyphCount > static_cast<std::size_t>(std::numeric_limits<int>::max())
            ? std::numeric_limits<int>::max()
            : static_cast<int>(info.glyphCount);
        const int utf8_range_size = info.utf8Range.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())
            ? std::numeric_limits<int>::max()
            : static_cast<int>(info.utf8Range.size());

        const auto &run_buffer = builder_.allocRunTextPos(info.fFont, glyph_count, utf8_range_size);
        if (run_buffer.utf8text != nullptr && utf8_text_ != nullptr) {
            std::memcpy(run_buffer.utf8text, utf8_text_ + info.utf8Range.begin(), static_cast<std::size_t>(utf8_range_size));
        }
        clusters_ = run_buffer.clusters;
        glyph_count_ = glyph_count;
        cluster_offset_ = info.utf8Range.begin();

        return {run_buffer.glyphs, run_buffer.points(), nullptr, run_buffer.clusters, current_position_};
    }

    void commitRunBuffer(const RunInfo &info) override {
        if (clusters_ != nullptr && cluster_offset_ <= std::numeric_limits<std::uint32_t>::max()) {
            const std::uint32_t offset = static_cast<std::uint32_t>(cluster_offset_);
            for (int i = 0; i < glyph_count_; ++i) {
                if (clusters_[i] >= offset) {
                    clusters_[i] -= offset;
                }
            }
        }
        current_position_ += info.fAdvance;
        advance_width_ = std::max(advance_width_, current_position_.fX);
    }

    void commitLine() override {}

private:
    SkTextBlobBuilder builder_;
    const char *utf8_text_ = nullptr;
    SkPoint current_position_ = SkPoint::Make(0.0f, 0.0f);
    float advance_width_ = 0.0f;
    std::uint32_t *clusters_ = nullptr;
    int glyph_count_ = 0;
    std::size_t cluster_offset_ = 0;
};


}  // namespace

std::size_t bytes_per_pixel(PixelFormat pixel_format) {
    switch (pixel_format) {
        case PixelFormat::Rgba32: return 4U;
        case PixelFormat::Gray8a: return 2U;
        case PixelFormat::Gray8:
        default: return 1U;
    }
}

bool valid_dimensions(int width, int height, PixelFormat pixel_format) {
    if (width <= 0 || height <= 0) {
        return false;
    }
    const std::size_t row_bytes = static_cast<std::size_t>(width) * bytes_per_pixel(pixel_format);
    const std::size_t rows = static_cast<std::size_t>(height);
    return width <= std::numeric_limits<int>::max() / static_cast<int>(bytes_per_pixel(pixel_format)) &&
           rows <= std::numeric_limits<std::size_t>::max() / row_bytes;
}

const char *pixel_format_name(PixelFormat pixel_format) {
    switch (pixel_format) {
        case PixelFormat::Rgba32: return "rgba32";
        case PixelFormat::Gray8a: return "gray8a";
        case PixelFormat::Gray8:
        default: return "gray8";
    }
}

struct TextState {
    sk_sp<SkFontMgr> font_mgr;
    std::string font_dir;
    std::string default_family;
};

RasterCanvas::RasterCanvas() = default;

RasterCanvas::~RasterCanvas() = default;

bool RasterCanvas::reset(int width, int height, PixelFormat pixel_format, const char *font_dir, const char *default_family) {
    if (pixel_format == PixelFormat::Gray8a || !valid_dimensions(width, height, pixel_format)) {
        return false;
    }

    const SkImageInfo info = pixel_format == PixelFormat::Rgba32
        ? SkImageInfo::Make(width, height, kN32_SkColorType, kPremul_SkAlphaType)
        : SkImageInfo::Make(width, height, kGray_8_SkColorType, kOpaque_SkAlphaType);
    const std::size_t row_bytes = static_cast<std::size_t>(width) * bytes_per_pixel(pixel_format);

    bitmap_.reset();
    canvas_.reset();
    text_.reset();
    if (!bitmap_.tryAllocPixels(info, row_bytes)) {
        return false;
    }
    pixel_format_ = pixel_format;
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

SkCanvas &RasterCanvas::sk_canvas() {
    return *canvas_;
}

TextState *RasterCanvas::text_state() {
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
    pixel_format_ = PixelFormat::Rgba32;
    width_ = bitmap_.width();
    height_ = bitmap_.height();
    return true;
}

bool RasterImage::reset(int width, int height, PixelFormat pixel_format, const std::vector<std::uint8_t> &pixels) {
    if (!valid_dimensions(width, height, pixel_format)) {
        return false;
    }
    const std::size_t expected = static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * bytes_per_pixel(pixel_format);
    if (pixels.size() != expected) {
        return false;
    }

    SkBitmap bitmap;
    if (pixel_format == PixelFormat::Gray8) {
        const SkImageInfo info = SkImageInfo::Make(width, height, kGray_8_SkColorType, kOpaque_SkAlphaType);
        if (!bitmap.tryAllocPixels(info, static_cast<std::size_t>(width))) {
            return false;
        }
        for (int y = 0; y < height; ++y) {
            std::uint8_t *row = static_cast<std::uint8_t *>(bitmap.getAddr(0, y));
            const std::uint8_t *src = pixels.data() + (static_cast<std::size_t>(y) * static_cast<std::size_t>(width));
            std::memcpy(row, src, static_cast<std::size_t>(width));
        }
    } else {
        const SkImageInfo info = SkImageInfo::Make(width, height, kN32_SkColorType, kPremul_SkAlphaType);
        if (!bitmap.tryAllocPixels(info)) {
            return false;
        }
        bitmap.erase(SK_ColorTRANSPARENT, SkIRect::MakeXYWH(0, 0, width, height));
        const bool gray_alpha = pixel_format == PixelFormat::Gray8a;
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                const std::size_t pixel_index = static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x);
                SkColor color = SK_ColorTRANSPARENT;
                if (gray_alpha) {
                    const std::size_t offset = pixel_index * 2U;
                    const std::uint8_t gray = pixels[offset];
                    const std::uint8_t alpha = pixels[offset + 1U];
                    color = SkColorSetARGB(alpha, gray, gray, gray);
                } else {
                    const std::size_t offset = pixel_index * 4U;
                    color = SkColorSetARGB(pixels[offset + 3U], pixels[offset], pixels[offset + 1U], pixels[offset + 2U]);
                }
                bitmap.erase(color, SkIRect::MakeXYWH(x, y, 1, 1));
            }
        }
    }

    bitmap.setImmutable();
    bitmap_ = bitmap;
    pixel_format_ = pixel_format;
    width_ = width;
    height_ = height;
    return true;
}

void clear(RasterCanvas &canvas, const NormalizedPaint &paint) {
    if (canvas.pixel_format() == PixelFormat::Rgba32) {
        canvas.sk_canvas().clear(rgba_color(paint));
        return;
    }

    SkBitmap &bitmap = canvas.bitmap();
    const int width = bitmap.width();
    const int height = bitmap.height();
    const std::uint8_t gray = luminance_byte(paint);
    for (int y = 0; y < height; ++y) {
        std::uint8_t *row = static_cast<std::uint8_t *>(bitmap.getAddr(0, y));
        std::memset(row, gray, static_cast<std::size_t>(width));
    }
}

bool draw_rect(RasterCanvas &canvas, float x, float y, float width, float height, const NormalizedPaint &paint) {
    if (!positive(width) || !positive(height)) {
        return false;
    }
    canvas.sk_canvas().drawRect(SkRect::MakeXYWH(x, y, width, height), skia_paint(canvas.pixel_format(), paint));
    return true;
}

bool draw_rounded_rect(RasterCanvas &canvas, float x, float y, float width, float height, float radius, const NormalizedPaint &paint) {
    if (!positive(width) || !positive(height) || !std::isfinite(radius)) {
        return false;
    }
    const SkScalar r = std::max(0.0f, radius);
    canvas.sk_canvas().drawRoundRect(SkRect::MakeXYWH(x, y, width, height), r, r, skia_paint(canvas.pixel_format(), paint));
    return true;
}

bool draw_rrect(RasterCanvas &canvas, float x, float y, float width, float height, const std::vector<float> &radii, const NormalizedPaint &paint) {
    if (!positive(width) || !positive(height) || radii.size() != 8) {
        return false;
    }
    SkVector corner_radii[4];
    for (std::size_t i = 0; i < 4; ++i) {
        const float rx = radii[i * 2];
        const float ry = radii[(i * 2) + 1];
        if (!std::isfinite(rx) || !std::isfinite(ry)) {
            return false;
        }
        corner_radii[i] = SkVector::Make(std::max(0.0f, rx), std::max(0.0f, ry));
    }
    SkRRect rrect;
    rrect.setRectRadii(SkRect::MakeXYWH(x, y, width, height), corner_radii);
    canvas.sk_canvas().drawRRect(rrect, skia_paint(canvas.pixel_format(), paint));
    return true;
}

bool draw_triangle(
    RasterCanvas &canvas,
    float x1,
    float y1,
    float x2,
    float y2,
    float x3,
    float y3,
    const NormalizedPaint &paint) {
    if (!finite_pair(x1, y1) || !finite_pair(x2, y2) || !finite_pair(x3, y3)) {
        return false;
    }

    SkPathBuilder builder;
    builder.moveTo(x1, y1);
    builder.lineTo(x2, y2);
    builder.lineTo(x3, y3);
    builder.close();

    canvas.sk_canvas().drawPath(builder.detach(), skia_paint(canvas.pixel_format(), paint));
    return true;
}

bool draw_circle(RasterCanvas &canvas, float cx, float cy, float radius, const NormalizedPaint &paint) {
    if (!std::isfinite(cx) || !std::isfinite(cy) || !positive(radius)) {
        return false;
    }
    canvas.sk_canvas().drawCircle(cx, cy, radius, skia_paint(canvas.pixel_format(), paint));
    return true;
}

bool save(RasterCanvas &canvas) {
    canvas.sk_canvas().save();
    return true;
}

bool restore(RasterCanvas &canvas) {
    if (canvas.sk_canvas().getSaveCount() <= 1) {
        return false;
    }
    canvas.sk_canvas().restore();
    return true;
}

bool translate(RasterCanvas &canvas, float x, float y) {
    if (!finite_pair(x, y)) {
        return false;
    }
    canvas.sk_canvas().translate(x, y);
    return true;
}

bool scale(RasterCanvas &canvas, float sx, float sy) {
    if (!finite_pair(sx, sy)) {
        return false;
    }
    canvas.sk_canvas().scale(sx, sy);
    return true;
}

bool clip_rect(RasterCanvas &canvas, float x, float y, float width, float height) {
    if (!finite_pair(x, y) || !positive(width) || !positive(height)) {
        return false;
    }
    canvas.sk_canvas().clipRect(SkRect::MakeXYWH(x, y, width, height));
    return true;
}

bool draw_line(RasterCanvas &canvas, float x1, float y1, float x2, float y2, const NormalizedPaint &paint) {
    if (!finite_pair(x1, y1) || !finite_pair(x2, y2) || !positive(paint.stroke_width)) {
        return false;
    }
    canvas.sk_canvas().drawLine(x1, y1, x2, y2, skia_paint(canvas.pixel_format(), paint));
    return true;
}

bool draw_path(RasterCanvas &canvas, const std::vector<float> &coords, bool closed, const NormalizedPaint &paint) {
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

    canvas.sk_canvas().drawPath(builder.detach(), skia_paint(canvas.pixel_format(), paint));
    return true;
}

bool draw_image(RasterCanvas &canvas, const RasterImage &image, float src_x, float src_y, float src_width, float src_height, float dst_x, float dst_y, float dst_width, float dst_height, float alpha) {
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

bool invert_rect(RasterCanvas &canvas, float x, float y, float width, float height) {
    if (!finite_pair(x, y) || !positive(width) || !positive(height)) {
        return false;
    }

    const int left = std::clamp(static_cast<int>(std::floor(x)), 0, canvas.width());
    const int top = std::clamp(static_cast<int>(std::floor(y)), 0, canvas.height());
    const int right = std::clamp(static_cast<int>(std::ceil(x + width)), 0, canvas.width());
    const int bottom = std::clamp(static_cast<int>(std::ceil(y + height)), 0, canvas.height());
    if (left >= right || top >= bottom) {
        return true;
    }

    SkBitmap &bitmap = canvas.bitmap();
    if (canvas.pixel_format() == PixelFormat::Gray8) {
        for (int row_index = top; row_index < bottom; ++row_index) {
            std::uint8_t *row = static_cast<std::uint8_t *>(bitmap.getAddr(left, row_index));
            for (int col = 0; col < right - left; ++col) {
                row[col] = static_cast<std::uint8_t>(255U - row[col]);
            }
        }
        return true;
    }

    for (int row_index = top; row_index < bottom; ++row_index) {
        for (int col = left; col < right; ++col) {
            const SkColor color = bitmap.getColor(col, row_index);
            const SkColor inverted = SkColorSetARGB(
                SkColorGetA(color),
                255U - SkColorGetR(color),
                255U - SkColorGetG(color),
                255U - SkColorGetB(color));
            bitmap.erase(inverted, SkIRect::MakeXYWH(col, row_index, 1, 1));
        }
    }
    return true;
}

bool convert_to_gray8(const RasterCanvas &source, RasterCanvas *destination, const GrayConversionOptions &options) {
    if (destination == nullptr || !destination->reset(source.width(), source.height(), PixelFormat::Gray8)) {
        return false;
    }

    SkBitmap &bitmap = destination->bitmap();
    for (int y = 0; y < source.height(); ++y) {
        auto *row = static_cast<std::uint8_t *>(bitmap.getAddr(0, y));
        for (int x = 0; x < source.width(); ++x) {
            row[x] = quantized_gray(sample_gray(source, x, y), options, x, y);
        }
    }
    return true;
}

bool quantize_rect(RasterCanvas &canvas, float x, float y, float width, float height, const GrayConversionOptions &options) {
    if (!finite_pair(x, y) || !positive(width) || !positive(height)) {
        return false;
    }
    if (options.quantize_gray_levels <= 1) {
        return true;
    }

    const int left = std::clamp(static_cast<int>(std::floor(x)), 0, canvas.width());
    const int top = std::clamp(static_cast<int>(std::floor(y)), 0, canvas.height());
    const int right = std::clamp(static_cast<int>(std::ceil(x + width)), 0, canvas.width());
    const int bottom = std::clamp(static_cast<int>(std::ceil(y + height)), 0, canvas.height());
    for (int row_index = top; row_index < bottom; ++row_index) {
        for (int col = left; col < right; ++col) {
            const std::uint8_t gray = quantized_gray(sample_gray(canvas, col, row_index), options, col, row_index);
            write_gray_pixel(canvas, col, row_index, gray);
        }
    }
    return true;
}

sk_sp<SkTypeface> select_typeface(RasterCanvas &canvas, const FontOptions &options, std::string *selected_family_out) {
    TextState *text = canvas.text_state();
    if (text == nullptr || !text->font_mgr) {
        return nullptr;
    }
    const std::string requested_family = options.family.empty() ? text->default_family : options.family;
    const SkFontStyle requested_style = font_style_from_options(options);
    sk_sp<SkTypeface> typeface(text->font_mgr->matchFamilyStyle(requested_family.c_str(), requested_style));
    if (typeface) {
        if (selected_family_out != nullptr) {
            *selected_family_out = requested_family;
        }
        return typeface;
    }
    if (!text->default_family.empty()) {
        typeface = text->font_mgr->matchFamilyStyle(text->default_family.c_str(), requested_style);
        if (typeface && selected_family_out != nullptr) {
            *selected_family_out = text->default_family;
        }
    }
    return typeface;
}

SkFont make_font(sk_sp<SkTypeface> typeface, float size) {
    SkFont font(std::move(typeface), size);
    font.setEdging(SkFont::Edging::kAntiAlias);
    return font;
}

float cap_height_for_font(const SkFont &font) {
    SkFontMetrics font_metrics;
    font.getMetrics(&font_metrics);
    float cap_height = std::abs(font_metrics.fCapHeight);
    if (!std::isfinite(cap_height) || cap_height <= 0.0f) {
        cap_height = std::abs(font_metrics.fAscent);
    }
    return std::isfinite(cap_height) ? std::ceil(cap_height) : 0.0f;
}

bool shape_text(RasterCanvas &canvas, const std::string &utf8, const FontOptions &font_options, const std::string &features_string, TextLine *line, std::string *error_message) {
    if (line == nullptr || !positive(font_options.size)) {
        if (error_message != nullptr) {
            *error_message = "shape-text requires a positive font size";
        }
        return false;
    }

    TextState *text = canvas.text_state();
    if (text == nullptr || !text->font_mgr) {
        if (error_message != nullptr) {
            *error_message = "shape-text requires a canvas created with a valid font directory";
        }
        return false;
    }

    TextLine next;
    next.utf8 = utf8;
    next.font_options = font_options;
    next.font_options.width = normalize_width(font_options.width);
    next.font_options.weight = normalize_weight(font_options.weight);
    next.features_string = features_string;
    if (!parse_features(features_string, &next.features, error_message)) {
        return false;
    }

    std::string selected_family;
    sk_sp<SkTypeface> typeface = select_typeface(canvas, next.font_options, &selected_family);
    if (!typeface) {
        if (error_message != nullptr) {
            *error_message = "shape-text could not resolve a typeface for family \"" + next.font_options.family + "\"";
        }
        return false;
    }
    next.font_options.family = selected_family;
    SkFont font = make_font(typeface, next.font_options.size);

    std::unique_ptr<SkShaper> shaper = SkShaper::Make(text->font_mgr);
    if (!shaper) {
        if (error_message != nullptr) {
            *error_message = "shape-text could not create Skia text shaper";
        }
        return false;
    }

    const char *data = utf8.c_str();
    const std::size_t size = utf8.size();
    std::unique_ptr<SkShaper::LanguageRunIterator> language = SkShaper::MakeStdLanguageRunIterator(data, size);
    std::unique_ptr<SkShaper::FontRunIterator> font_runs = SkShaper::MakeFontMgrRunIterator(
        data,
        size,
        font,
        text->font_mgr,
        next.font_options.family.c_str(),
        font_style_from_options(next.font_options),
        language.get());
    std::unique_ptr<SkShaper::BiDiRunIterator> bidi = SkShaper::MakeBiDiRunIterator(data, size, 0);
    std::unique_ptr<SkShaper::ScriptRunIterator> script = SkShapers::HB::ScriptRunIterator(data, size);
    if (!language || !font_runs || !bidi || !script) {
        if (error_message != nullptr) {
            *error_message = "shape-text could not create Skia text run iterators";
        }
        return false;
    }

    TextLineRunHandler handler(data);
    const SkShaper::Feature *feature_data = next.features.empty() ? nullptr : next.features.data();
    shaper->shape(
        data,
        size,
        *font_runs,
        *bidi,
        *script,
        *language,
        feature_data,
        next.features.size(),
        std::numeric_limits<SkScalar>::infinity(),
        &handler);

    next.blob = handler.make_blob();
    next.metrics.width = std::ceil(std::max(0.0f, handler.advance_width()));
    next.metrics.height = cap_height_for_font(font);
    *line = std::move(next);
    return true;
}

bool draw_text_line(RasterCanvas &canvas, const TextLine &line, float x, float y, const NormalizedPaint &paint) {
    if (!finite_pair(x, y) || !line.blob) {
        return false;
    }
    canvas.sk_canvas().drawTextBlob(line.blob, x, y + line.metrics.height, skia_paint(canvas.pixel_format(), paint));
    return true;
}

std::uint8_t sample_gray(const RasterCanvas &canvas, int x, int y) {
    const SkBitmap &bitmap = canvas.bitmap();
    if (x < 0 || y < 0 || x >= bitmap.width() || y >= bitmap.height()) {
        return 0;
    }
    if (canvas.pixel_format() == PixelFormat::Rgba32) {
        const SkColor color = bitmap.getColor(x, y);
        const float gray = (0.299f * static_cast<float>(SkColorGetR(color))) +
                           (0.587f * static_cast<float>(SkColorGetG(color))) +
                           (0.114f * static_cast<float>(SkColorGetB(color)));
        return static_cast<std::uint8_t>(std::clamp(std::lround(gray), 0L, 255L));
    }
    const std::uint8_t *row = static_cast<const std::uint8_t *>(bitmap.getAddr(0, y));
    return row[x];
}

RgbaPixel sample_rgba(const RasterCanvas &canvas, int x, int y) {
    const SkBitmap &bitmap = canvas.bitmap();
    if (x < 0 || y < 0 || x >= bitmap.width() || y >= bitmap.height()) {
        return {};
    }
    if (canvas.pixel_format() == PixelFormat::Gray8) {
        const std::uint8_t gray = sample_gray(canvas, x, y);
        return {gray, gray, gray, 255};
    }
    const SkColor color = bitmap.getColor(x, y);
    return {
        static_cast<std::uint8_t>(SkColorGetR(color)),
        static_cast<std::uint8_t>(SkColorGetG(color)),
        static_cast<std::uint8_t>(SkColorGetB(color)),
        static_cast<std::uint8_t>(SkColorGetA(color)),
    };
}

CanvasStats compute_stats(const RasterCanvas &canvas) {
    const SkBitmap &bitmap = canvas.bitmap();
    CanvasStats stats;
    stats.width = bitmap.width();
    stats.height = bitmap.height();
    stats.pixel_format = canvas.pixel_format();
    stats.min_gray = 255;
    stats.max_gray = 0;
    stats.checksum = kFnvOffset;

    bool seen[256] = {false};
    for (int y = 0; y < stats.height; ++y) {
        for (int x = 0; x < stats.width; ++x) {
            const RgbaPixel rgba = sample_rgba(canvas, x, y);
            const std::uint8_t gray = sample_gray(canvas, x, y);
            stats.min_gray = std::min(stats.min_gray, static_cast<int>(gray));
            stats.max_gray = std::max(stats.max_gray, static_cast<int>(gray));
            if (!seen[gray]) {
                seen[gray] = true;
                ++stats.gray_shades;
            }
            if (rgba.r != 255 || rgba.g != 255 || rgba.b != 255 || rgba.a != 255) {
                ++stats.non_white_pixels;
            }
            stats.checksum ^= rgba.r;
            stats.checksum *= kFnvPrime;
            stats.checksum ^= rgba.g;
            stats.checksum *= kFnvPrime;
            stats.checksum ^= rgba.b;
            stats.checksum *= kFnvPrime;
            stats.checksum ^= rgba.a;
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

void canvas_to_rgba32(const RasterCanvas &canvas, std::vector<std::uint8_t> *rgba) {
    const int width = canvas.width();
    const int height = canvas.height();
    rgba->assign(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U, 0);

    for (int y = 0; y < height; ++y) {
        std::uint8_t *dst = rgba->data() + static_cast<std::size_t>(y) * static_cast<std::size_t>(width) * 4U;
        for (int x = 0; x < width; ++x) {
            const RgbaPixel pixel = sample_rgba(canvas, x, y);
            dst[x * 4 + 0] = pixel.r;
            dst[x * 4 + 1] = pixel.g;
            dst[x * 4 + 2] = pixel.b;
            dst[x * 4 + 3] = pixel.a;
        }
    }
}

}  // namespace otter
