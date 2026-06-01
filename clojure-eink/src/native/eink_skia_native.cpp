#include "eink_skia_native.h"

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cmath>
#include <cstdarg>
#include <cstdlib>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <limits>
#include <memory>
#include <new>
#include <string>
#include <unordered_map>
#include <vector>

#include "core/SkCanvas.h"
#include "core/SkColor.h"
#include "core/SkFontMgr.h"
#include "core/SkFontStyle.h"
#include "core/SkImageInfo.h"
#include "core/SkPaint.h"
#include "core/SkPath.h"
#include "core/SkPathBuilder.h"
#include "core/SkRect.h"
#include "core/SkRefCnt.h"
#include "core/SkString.h"
#include "core/SkSurface.h"
#include "core/SkTypes.h"
#include "modules/skparagraph/include/FontCollection.h"
#include "modules/skparagraph/include/Metrics.h"
#include "modules/skparagraph/include/Paragraph.h"
#include "modules/skparagraph/include/ParagraphBuilder.h"
#include "modules/skparagraph/include/ParagraphStyle.h"
#include "modules/skparagraph/include/TextStyle.h"
#include "modules/skunicode/include/SkUnicode_icu.h"
#include "ports/SkFontMgr_directory.h"
#include "fbink.h"

namespace {
namespace textlayout = skia::textlayout;

thread_local char last_error[512] = "";

constexpr size_t TEXT_CACHE_MAX_ENTRIES = 512;

struct TextCacheKey {
    std::string utf8;
    std::string family;
    float size = 0.0f;
    int weight = 0;
    int slant = 0;
    float max_width = 0.0f;
    uint32_t color = 0;

    bool operator==(const TextCacheKey &other) const {
        return utf8 == other.utf8 && family == other.family && size == other.size &&
               weight == other.weight && slant == other.slant && max_width == other.max_width &&
               color == other.color;
    }
};

uint32_t float_bits(float value) {
    uint32_t bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));
    return bits;
}

void hash_combine(size_t *seed, size_t value) {
    *seed ^= value + 0x9e3779b97f4a7c15ULL + (*seed << 6) + (*seed >> 2);
}

struct TextCacheKeyHash {
    size_t operator()(const TextCacheKey &key) const {
        size_t seed = std::hash<std::string>{}(key.utf8);
        hash_combine(&seed, std::hash<std::string>{}(key.family));
        hash_combine(&seed, std::hash<uint32_t>{}(float_bits(key.size)));
        hash_combine(&seed, std::hash<int>{}(key.weight));
        hash_combine(&seed, std::hash<int>{}(key.slant));
        hash_combine(&seed, std::hash<uint32_t>{}(float_bits(key.max_width)));
        hash_combine(&seed, std::hash<uint32_t>{}(key.color));
        return seed;
    }
};

struct TextCacheEntry {
    std::shared_ptr<textlayout::Paragraph> paragraph;
    uint64_t last_used = 0;
};

struct eink_skia_context {
    int width;
    int height;
    int stride;
    std::vector<uint8_t> pixels;
    std::vector<uint8_t> previous_pixels;
    sk_sp<SkSurface> surface;
    SkCanvas *canvas;
    SkPaint paint;
    sk_sp<SkFontMgr> font_mgr;
    sk_sp<textlayout::FontCollection> font_collection;
    sk_sp<SkUnicode> unicode;
    std::string font_dir;
    std::string default_family;
    std::unordered_map<TextCacheKey, TextCacheEntry, TextCacheKeyHash> text_cache;
    uint64_t text_cache_tick = 0;
    int text_cache_hits = 0;
    int text_cache_misses = 0;
    int text_cache_evictions = 0;
    int fbink_fd = -1;
    bool fbink_initialized = false;
    FBInkConfig fbink_cfg{};
    FBInkState fbink_state{};
};

void set_error(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(last_error, sizeof(last_error), fmt, ap);
    va_end(ap);
}

void clear_error() {
    last_error[0] = '\0';
}

int fail_with_code(int code, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(last_error, sizeof(last_error), fmt, ap);
    va_end(ap);
    return -code;
}

int fail_with_errno(const char *what, int code) {
    return fail_with_code(code, "%s: %s", what, strerror(code));
}

WFM_MODE_INDEX_T decode_waveform(int waveform) {
    switch (waveform) {
        case 1:
            return WFM_DU;
        case 2:
            return WFM_GC16;
        case 3:
            return WFM_GL16;
        case 4:
            return WFM_A2;
        case 0:
        default:
            return WFM_AUTO;
    }
}

uint8_t color_component(float value) {
    if (!std::isfinite(value)) {
        value = 0.0f;
    }
    float clamped = std::clamp(value, 0.0f, 1.0f);
    return static_cast<uint8_t>(std::lround(clamped * 255.0f));
}

SkPaint::Style decode_style(int style) {
    switch (style) {
        case 1:
            return SkPaint::kStroke_Style;
        case 2:
            return SkPaint::kStrokeAndFill_Style;
        case 0:
        default:
            return SkPaint::kFill_Style;
    }
}

bool checked_buffer_len(int width, int height, size_t *out_len) {
    if (width <= 0 || height <= 0) {
        return false;
    }

    size_t row_bytes = static_cast<size_t>(width);
    size_t rows = static_cast<size_t>(height);
    if (rows > std::numeric_limits<size_t>::max() / row_bytes) {
        return false;
    }

    *out_len = row_bytes * rows;
    return true;
}

eink_skia_context *as_context(void *ctx, const char *function_name) {
    if (ctx == nullptr) {
        set_error("%s: context is NULL", function_name);
        return nullptr;
    }
    return static_cast<eink_skia_context *>(ctx);
}

int ensure_positive_rect(const char *function_name, float width, float height) {
    if (!(width > 0.0f) || !(height > 0.0f)) {
        return fail_with_code(EINVAL,
                              "%s: invalid rectangle width=%g height=%g",
                              function_name,
                              static_cast<double>(width),
                              static_cast<double>(height));
    }
    return 0;
}

bool has_supported_font_extension(const std::filesystem::path &path) {
    std::string extension = path.extension().string();
    std::transform(extension.begin(),
                   extension.end(),
                   extension.begin(),
                   [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    return extension == ".ttf" || extension == ".otf" || extension == ".ttc";
}

int validate_font_dir(const char *font_dir, std::string *out_path) {
    if (font_dir == nullptr || font_dir[0] == '\0') {
        return fail_with_code(EINVAL, "eink_skia_create: font directory is required (EINK_FONT_DIR)");
    }

    std::filesystem::path dir(font_dir);
    std::error_code ec;
    std::filesystem::file_status status = std::filesystem::status(dir, ec);
    if (ec || !std::filesystem::exists(status)) {
        return fail_with_code(EINVAL,
                              "eink_skia_create: font directory does not exist: %s",
                              font_dir);
    }
    if (!std::filesystem::is_directory(status)) {
        return fail_with_code(EINVAL,
                              "eink_skia_create: font directory is not a directory: %s",
                              font_dir);
    }

    bool found_font = false;
    std::filesystem::directory_iterator it(dir,
                                           std::filesystem::directory_options::skip_permission_denied,
                                           ec);
    if (ec) {
        return fail_with_code(EINVAL,
                              "eink_skia_create: font directory cannot be read: %s",
                              font_dir);
    }
    for (std::filesystem::directory_iterator end; it != end; it.increment(ec)) {
        if (ec) {
            ec.clear();
            continue;
        }
        std::filesystem::file_status entry_status = it->status(ec);
        if (ec) {
            ec.clear();
            continue;
        }
        if (std::filesystem::is_regular_file(entry_status) && has_supported_font_extension(it->path())) {
            found_font = true;
            break;
        }
    }

    if (!found_font) {
        return fail_with_code(EINVAL,
                              "eink_skia_create: font directory is empty: %s",
                              font_dir);
    }

    *out_path = dir.string();
    return 0;
}

SkFontStyle::Slant decode_slant(int slant) {
    switch (slant) {
        case 1:
            return SkFontStyle::kItalic_Slant;
        case 2:
            return SkFontStyle::kOblique_Slant;
        case 0:
        default:
            return SkFontStyle::kUpright_Slant;
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

const char *select_family(eink_skia_context *context, const char *family) {
    if (family != nullptr && family[0] != '\0') {
        return family;
    }
    return context->default_family.c_str();
}

int close_fbink(eink_skia_context *context) {
    if (context->fbink_fd < 0) {
        context->fbink_initialized = false;
        return 0;
    }

    int rv = fbink_close(context->fbink_fd);
    context->fbink_fd = -1;
    context->fbink_initialized = false;
    if (rv != EXIT_SUCCESS) {
        return fail_with_code(EIO, "fbink_close failed with rv=%d", rv);
    }

    return 0;
}

int ensure_fbink(eink_skia_context *context) {
    if (context->fbink_initialized && context->fbink_fd >= 0) {
        return 0;
    }

    context->fbink_cfg = FBInkConfig{};
    context->fbink_state = FBInkState{};
    context->fbink_cfg.is_quiet = true;
    context->fbink_cfg.is_verbose = false;

    context->fbink_fd = fbink_open();
    if (context->fbink_fd < 0) {
        return fail_with_errno("fbink_open", errno ? errno : ENODEV);
    }

    int rv = fbink_init(context->fbink_fd, &context->fbink_cfg);
    if (rv != EXIT_SUCCESS) {
        int saved = errno ? errno : EIO;
        fbink_close(context->fbink_fd);
        context->fbink_fd = -1;
        context->fbink_initialized = false;
        return fail_with_errno("fbink_init", saved);
    }

    fbink_get_state(&context->fbink_cfg, &context->fbink_state);
    context->fbink_initialized = true;
    clear_error();
    return 0;
}

int canonical_slant(int slant) {
    switch (slant) {
        case 1:
            return 1;
        case 2:
            return 2;
        case 0:
        default:
            return 0;
    }
}


bool make_text_cache_key(eink_skia_context *context,
                         const char *function_name,
                         const char *utf8,
                         int utf8_len,
                         const char *family,
                         float size,
                         int weight,
                         int slant,
                         float max_width,
                         TextCacheKey *out_key) {
    if (utf8 == nullptr) {
        fail_with_code(EINVAL, "%s: utf8 is NULL", function_name);
        return false;
    }
    if (utf8_len < 0) {
        fail_with_code(EINVAL, "%s: invalid utf8_len=%d", function_name, utf8_len);
        return false;
    }
    if (!(size > 0.0f) || !std::isfinite(size)) {
        fail_with_code(EINVAL, "%s: invalid size=%g", function_name, static_cast<double>(size));
        return false;
    }
    if (!(max_width > 0.0f) || !std::isfinite(max_width)) {
        fail_with_code(EINVAL,
                       "%s: invalid max_width=%g",
                       function_name,
                       static_cast<double>(max_width));
        return false;
    }
    if (!context->font_collection || !context->unicode) {
        fail_with_code(EINVAL, "%s: font collection is not initialized", function_name);
        return false;
    }

    out_key->utf8.assign(utf8, static_cast<size_t>(utf8_len));
    out_key->family = select_family(context, family);
    out_key->size = size;
    out_key->weight = normalize_weight(weight);
    out_key->slant = canonical_slant(slant);
    out_key->max_width = max_width;
    out_key->color = context->paint.getColor();
    return true;
}

std::shared_ptr<textlayout::Paragraph> build_paragraph(eink_skia_context *context,
                                                        const char *function_name,
                                                        const TextCacheKey &key) {
    SkPaint foreground = context->paint;
    foreground.setStyle(SkPaint::kFill_Style);
    foreground.setColor(key.color);

    textlayout::TextStyle text_style;
    text_style.setForegroundPaint(foreground);
    text_style.setColor(key.color);
    text_style.setFontSize(key.size);
    text_style.setFontStyle(SkFontStyle(key.weight,
                                        SkFontStyle::kNormal_Width,
                                        decode_slant(key.slant)));
    text_style.setFontFamilies({SkString(key.family.c_str())});
    text_style.setTextBaseline(textlayout::TextBaseline::kAlphabetic);

    textlayout::ParagraphStyle paragraph_style;
    paragraph_style.setTextDirection(textlayout::TextDirection::kLtr);
    paragraph_style.setTextStyle(text_style);

    auto builder = textlayout::ParagraphBuilder::make(paragraph_style,
                                                      context->font_collection,
                                                      context->unicode);
    if (!builder) {
        fail_with_code(EINVAL, "%s: failed to create paragraph builder", function_name);
        return nullptr;
    }

    builder->addText(key.utf8.c_str(), key.utf8.size());
    auto built = builder->Build();
    if (!built) {
        fail_with_code(EINVAL, "%s: failed to build paragraph", function_name);
        return nullptr;
    }

    built->layout(key.max_width);
    return std::shared_ptr<textlayout::Paragraph>(built.release());
}

void evict_text_cache_if_needed(eink_skia_context *context) {
    if (context->text_cache.size() <= TEXT_CACHE_MAX_ENTRIES) {
        return;
    }

    auto victim = std::min_element(context->text_cache.begin(),
                                   context->text_cache.end(),
                                   [](const auto &a, const auto &b) {
                                       return a.second.last_used < b.second.last_used;
                                   });
    if (victim != context->text_cache.end()) {
        context->text_cache.erase(victim);
        ++context->text_cache_evictions;
    }
}

std::shared_ptr<textlayout::Paragraph> make_paragraph(eink_skia_context *context,
                                                       const char *function_name,
                                                       const char *utf8,
                                                       int utf8_len,
                                                       const char *family,
                                                       float size,
                                                       int weight,
                                                       int slant,
                                                       float max_width) {
    TextCacheKey key;
    if (!make_text_cache_key(context,
                             function_name,
                             utf8,
                             utf8_len,
                             family,
                             size,
                             weight,
                             slant,
                             max_width,
                             &key)) {
        return nullptr;
    }

    uint64_t tick = ++context->text_cache_tick;
    auto found = context->text_cache.find(key);
    if (found != context->text_cache.end()) {
        found->second.last_used = tick;
        ++context->text_cache_hits;
        return found->second.paragraph;
    }

    auto paragraph = build_paragraph(context, function_name, key);
    if (!paragraph) {
        return nullptr;
    }

    ++context->text_cache_misses;
    context->text_cache.emplace(std::move(key), TextCacheEntry{paragraph, tick});
    evict_text_cache_if_needed(context);
    return paragraph;
}

enum BatchCommand : uint8_t {
    CMD_SAVE = 1,
    CMD_RESTORE = 2,
    CMD_TRANSLATE = 3,
    CMD_SCALE = 4,
    CMD_CLIP_RECT = 5,
    CMD_SET_COLOR = 6,
    CMD_SET_STYLE = 7,
    CMD_SET_STROKE_WIDTH = 8,
    CMD_DRAW_RECT = 9,
    CMD_DRAW_ROUND_RECT = 10,
    CMD_DRAW_PATH = 11,
    CMD_DRAW_TEXT_BOX = 12,
};

struct CommandReader {
    const unsigned char *data;
    size_t len;
    size_t offset;
};

bool read_bytes(CommandReader *reader, void *out, size_t n, const char *what) {
    if (n > reader->len - reader->offset) {
        fail_with_code(EINVAL,
                       "eink_skia_replay_commands: truncated %s at offset=%zu need=%zu len=%zu",
                       what,
                       reader->offset,
                       n,
                       reader->len);
        return false;
    }
    std::memcpy(out, reader->data + reader->offset, n);
    reader->offset += n;
    return true;
}

bool read_u8(CommandReader *reader, uint8_t *out, const char *what) {
    return read_bytes(reader, out, sizeof(*out), what);
}

bool read_i32(CommandReader *reader, int32_t *out, const char *what) {
    return read_bytes(reader, out, sizeof(*out), what);
}

bool read_f32(CommandReader *reader, float *out, const char *what) {
    return read_bytes(reader, out, sizeof(*out), what);
}

bool read_string(CommandReader *reader, int32_t len, std::string *out, const char *what) {
    if (len < 0) {
        fail_with_code(EINVAL, "eink_skia_replay_commands: invalid %s length=%d", what, len);
        return false;
    }
    if (static_cast<size_t>(len) > reader->len - reader->offset) {
        fail_with_code(EINVAL,
                       "eink_skia_replay_commands: truncated %s at offset=%zu need=%d len=%zu",
                       what,
                       reader->offset,
                       len,
                       reader->len);
        return false;
    }
    out->assign(reinterpret_cast<const char *>(reader->data + reader->offset), static_cast<size_t>(len));
    reader->offset += static_cast<size_t>(len);
    return true;
}

int replay_set_color(eink_skia_context *context, CommandReader *reader) {
    float r = 0.0f;
    float g = 0.0f;
    float b = 0.0f;
    float a = 1.0f;
    if (!read_f32(reader, &r, "set-color.r") || !read_f32(reader, &g, "set-color.g") ||
        !read_f32(reader, &b, "set-color.b") || !read_f32(reader, &a, "set-color.a")) {
        return -EINVAL;
    }
    context->paint.setColor(SkColorSetARGB(color_component(a),
                                           color_component(r),
                                           color_component(g),
                                           color_component(b)));
    return 0;
}

int replay_rect_args(CommandReader *reader, const char *name, float *x, float *y, float *width, float *height) {
    if (!read_f32(reader, x, name) || !read_f32(reader, y, name) ||
        !read_f32(reader, width, name) || !read_f32(reader, height, name)) {
        return -EINVAL;
    }
    return ensure_positive_rect("eink_skia_replay_commands", *width, *height);
}

int replay_path(eink_skia_context *context, CommandReader *reader) {
    int32_t point_count = 0;
    int32_t closed = 0;
    if (!read_i32(reader, &point_count, "draw-path.point-count") ||
        !read_i32(reader, &closed, "draw-path.closed")) {
        return -EINVAL;
    }
    if (point_count <= 0) {
        return fail_with_code(EINVAL,
                              "eink_skia_replay_commands: invalid path point_count=%d",
                              point_count);
    }

    float x = 0.0f;
    float y = 0.0f;
    if (!read_f32(reader, &x, "draw-path.x0") || !read_f32(reader, &y, "draw-path.y0")) {
        return -EINVAL;
    }

    SkPathBuilder builder;
    builder.moveTo(x, y);
    for (int32_t idx = 1; idx < point_count; ++idx) {
        if (!read_f32(reader, &x, "draw-path.x") || !read_f32(reader, &y, "draw-path.y")) {
            return -EINVAL;
        }
        builder.lineTo(x, y);
    }
    if (closed != 0) {
        builder.close();
    }
    context->canvas->drawPath(builder.detach(), context->paint);
    return 0;
}

int replay_text_box(eink_skia_context *context, CommandReader *reader) {
    int32_t text_len = 0;
    int32_t family_len = 0;
    float size = 0.0f;
    int32_t weight = 0;
    int32_t slant = 0;
    float x = 0.0f;
    float y = 0.0f;
    float max_width = 0.0f;
    if (!read_i32(reader, &text_len, "draw-text-box.text-len") ||
        !read_i32(reader, &family_len, "draw-text-box.family-len") ||
        !read_f32(reader, &size, "draw-text-box.size") ||
        !read_i32(reader, &weight, "draw-text-box.weight") ||
        !read_i32(reader, &slant, "draw-text-box.slant") ||
        !read_f32(reader, &x, "draw-text-box.x") ||
        !read_f32(reader, &y, "draw-text-box.y") ||
        !read_f32(reader, &max_width, "draw-text-box.max-width")) {
        return -EINVAL;
    }

    std::string text;
    std::string family;
    if (!read_string(reader, text_len, &text, "draw-text-box.text") ||
        !read_string(reader, family_len, &family, "draw-text-box.family")) {
        return -EINVAL;
    }

    auto paragraph = make_paragraph(context,
                                    "eink_skia_replay_commands",
                                    text.data(),
                                    static_cast<int>(text.size()),
                                    family.empty() ? nullptr : family.c_str(),
                                    size,
                                    weight,
                                    slant,
                                    max_width);
    if (!paragraph) {
        return -EINVAL;
    }
    paragraph->paint(context->canvas, x, y);
    return 0;
}

} // namespace

const char *eink_skia_last_error(void) {
    return last_error;
}

void *eink_skia_create(int width,
                       int height,
                       const char *font_dir,
                       const char *default_family) {
    size_t pixel_count = 0;
    if (!checked_buffer_len(width, height, &pixel_count)) {
        set_error("eink_skia_create: invalid dimensions width=%d height=%d", width, height);
        return nullptr;
    }

    std::string font_dir_path;
    if (validate_font_dir(font_dir, &font_dir_path) != 0) {
        return nullptr;
    }

    try {
        auto *ctx = new eink_skia_context();
        ctx->width = width;
        ctx->height = height;
        ctx->stride = width;
        ctx->pixels.assign(pixel_count, 0xFF);
        ctx->previous_pixels.assign(pixel_count, 0xFF);
        ctx->canvas = nullptr;
        ctx->paint.setAntiAlias(true);
        ctx->paint.setStyle(SkPaint::kFill_Style);
        ctx->paint.setColor(SK_ColorBLACK);
        ctx->font_dir = font_dir_path;

        ctx->font_mgr = SkFontMgr_New_Custom_Directory(ctx->font_dir.c_str());
        if (!ctx->font_mgr) {
            set_error("eink_skia_create: failed to create font manager for %s", font_dir_path.c_str());
            delete ctx;
            return nullptr;
        }
        if (ctx->font_mgr->countFamilies() <= 0) {
            delete ctx;
            set_error("eink_skia_create: font directory has no usable font families: %s", font_dir);
            return nullptr;
        }

        if (default_family != nullptr && default_family[0] != '\0') {
            ctx->default_family = default_family;
        } else {
            SkString family_name;
            ctx->font_mgr->getFamilyName(0, &family_name);
            ctx->default_family = family_name.c_str();
        }

        ctx->unicode = SkUnicodes::ICU::Make();
        if (!ctx->unicode) {
            delete ctx;
            set_error("eink_skia_create: failed to initialize ICU SkUnicode");
            return nullptr;
        }

        ctx->font_collection = sk_make_sp<textlayout::FontCollection>();
        ctx->font_collection->setDefaultFontManager(ctx->font_mgr, ctx->default_family.c_str());
        ctx->font_collection->enableFontFallback();

        SkImageInfo info = SkImageInfo::Make(width,
                                             height,
                                             kGray_8_SkColorType,
                                             kOpaque_SkAlphaType);
        ctx->surface = SkSurfaces::WrapPixels(info, ctx->pixels.data(), static_cast<size_t>(ctx->stride));
        if (!ctx->surface) {
            delete ctx;
            set_error("eink_skia_create: failed to wrap gray8 pixels width=%d height=%d", width, height);
            return nullptr;
        }
        ctx->canvas = ctx->surface->getCanvas();
        clear_error();
        return ctx;
    } catch (const std::bad_alloc &) {
        set_error("eink_skia_create: allocation failed for width=%d height=%d", width, height);
        return nullptr;
    } catch (const std::exception &ex) {
        set_error("eink_skia_create: unexpected error: %s", ex.what());
        return nullptr;
    } catch (...) {
        set_error("eink_skia_create: unexpected error");
        return nullptr;
    }
}

int eink_skia_destroy(void *ctx) {
    eink_skia_context *context = as_context(ctx, "eink_skia_destroy");
    if (context == nullptr) {
        return -EINVAL;
    }

    int rv = close_fbink(context);
    delete context;
    if (rv != 0) {
        return rv;
    }

    clear_error();
    return 0;
}

int eink_skia_width(void *ctx) {
    eink_skia_context *context = as_context(ctx, "eink_skia_width");
    if (context == nullptr) {
        return -EINVAL;
    }

    clear_error();
    return context->width;
}

int eink_skia_height(void *ctx) {
    eink_skia_context *context = as_context(ctx, "eink_skia_height");
    if (context == nullptr) {
        return -EINVAL;
    }

    clear_error();
    return context->height;
}

int eink_skia_stride(void *ctx) {
    eink_skia_context *context = as_context(ctx, "eink_skia_stride");
    if (context == nullptr) {
        return -EINVAL;
    }

    clear_error();
    return context->stride;
}

int eink_skia_clear(void *ctx, unsigned char gray) {
    eink_skia_context *context = as_context(ctx, "eink_skia_clear");
    if (context == nullptr) {
        return -EINVAL;
    }

    std::fill(context->pixels.begin(), context->pixels.end(), static_cast<uint8_t>(gray));
    clear_error();
    return 0;
}

int eink_skia_save(void *ctx) {
    eink_skia_context *context = as_context(ctx, "eink_skia_save");
    if (context == nullptr) {
        return -EINVAL;
    }

    context->canvas->save();
    clear_error();
    return 0;
}

int eink_skia_restore(void *ctx) {
    eink_skia_context *context = as_context(ctx, "eink_skia_restore");
    if (context == nullptr) {
        return -EINVAL;
    }

    context->canvas->restore();
    clear_error();
    return 0;
}

int eink_skia_translate(void *ctx, float x, float y) {
    eink_skia_context *context = as_context(ctx, "eink_skia_translate");
    if (context == nullptr) {
        return -EINVAL;
    }

    context->canvas->translate(x, y);
    clear_error();
    return 0;
}

int eink_skia_scale(void *ctx, float sx, float sy) {
    eink_skia_context *context = as_context(ctx, "eink_skia_scale");
    if (context == nullptr) {
        return -EINVAL;
    }

    context->canvas->scale(sx, sy);
    clear_error();
    return 0;
}

int eink_skia_clip_rect(void *ctx, float x, float y, float width, float height) {
    eink_skia_context *context = as_context(ctx, "eink_skia_clip_rect");
    if (context == nullptr) {
        return -EINVAL;
    }
    int valid = ensure_positive_rect("eink_skia_clip_rect", width, height);
    if (valid != 0) {
        return valid;
    }

    context->canvas->clipRect(SkRect::MakeXYWH(x, y, width, height), true);
    clear_error();
    return 0;
}

int eink_skia_set_color(void *ctx, float r, float g, float b, float a) {
    eink_skia_context *context = as_context(ctx, "eink_skia_set_color");
    if (context == nullptr) {
        return -EINVAL;
    }

    context->paint.setColor(SkColorSetARGB(color_component(a),
                                           color_component(r),
                                           color_component(g),
                                           color_component(b)));
    clear_error();
    return 0;
}

int eink_skia_set_style(void *ctx, int style) {
    eink_skia_context *context = as_context(ctx, "eink_skia_set_style");
    if (context == nullptr) {
        return -EINVAL;
    }

    context->paint.setStyle(decode_style(style));
    clear_error();
    return 0;
}

int eink_skia_set_stroke_width(void *ctx, float width) {
    eink_skia_context *context = as_context(ctx, "eink_skia_set_stroke_width");
    if (context == nullptr) {
        return -EINVAL;
    }
    if (!(width >= 0.0f)) {
        return fail_with_code(EINVAL,
                              "eink_skia_set_stroke_width: invalid width=%g",
                              static_cast<double>(width));
    }

    context->paint.setStrokeWidth(width);
    clear_error();
    return 0;
}

int eink_skia_draw_rect(void *ctx, float x, float y, float width, float height) {
    eink_skia_context *context = as_context(ctx, "eink_skia_draw_rect");
    if (context == nullptr) {
        return -EINVAL;
    }
    int valid = ensure_positive_rect("eink_skia_draw_rect", width, height);
    if (valid != 0) {
        return valid;
    }

    context->canvas->drawRect(SkRect::MakeXYWH(x, y, width, height), context->paint);
    clear_error();
    return 0;
}

int eink_skia_draw_round_rect(void *ctx, float x, float y, float width, float height, float radius) {
    eink_skia_context *context = as_context(ctx, "eink_skia_draw_round_rect");
    if (context == nullptr) {
        return -EINVAL;
    }
    int valid = ensure_positive_rect("eink_skia_draw_round_rect", width, height);
    if (valid != 0) {
        return valid;
    }

    SkScalar r = std::max(0.0f, radius);
    context->canvas->drawRoundRect(SkRect::MakeXYWH(x, y, width, height), r, r, context->paint);
    clear_error();
    return 0;
}

int eink_skia_draw_path(void *ctx, const float *xy_pairs, int point_count, int closed) {
    eink_skia_context *context = as_context(ctx, "eink_skia_draw_path");
    if (context == nullptr) {
        return -EINVAL;
    }
    if (xy_pairs == nullptr) {
        return fail_with_code(EINVAL, "eink_skia_draw_path: xy_pairs is NULL");
    }
    if (point_count <= 0) {
        return fail_with_code(EINVAL, "eink_skia_draw_path: invalid point_count=%d", point_count);
    }

    SkPathBuilder builder;
    builder.moveTo(xy_pairs[0], xy_pairs[1]);
    for (int idx = 1; idx < point_count; ++idx) {
        builder.lineTo(xy_pairs[idx * 2], xy_pairs[idx * 2 + 1]);
    }
    if (closed != 0) {
        builder.close();
    }
    context->canvas->drawPath(builder.detach(), context->paint);
    clear_error();
    return 0;
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
    eink_skia_context *context = as_context(ctx, "eink_skia_text_bounds");
    if (context == nullptr) {
        return -EINVAL;
    }
    if (out_width == nullptr || out_height == nullptr || out_ascent == nullptr ||
        out_descent == nullptr || out_leading == nullptr) {
        return fail_with_code(EINVAL, "eink_skia_text_bounds: output pointer is NULL");
    }

    auto paragraph = make_paragraph(context,
                                    "eink_skia_text_bounds",
                                    utf8,
                                    utf8_len,
                                    family,
                                    size,
                                    weight,
                                    slant,
                                    max_width);
    if (!paragraph) {
        return -EINVAL;
    }

    *out_width = paragraph->getLongestLine();
    *out_height = paragraph->getHeight();

    std::vector<textlayout::LineMetrics> line_metrics;
    paragraph->getLineMetrics(line_metrics);
    if (!line_metrics.empty()) {
        const textlayout::LineMetrics &first = line_metrics.front();
        *out_ascent = static_cast<float>(first.fAscent);
        *out_descent = static_cast<float>(first.fDescent);
        *out_leading = static_cast<float>(std::max(0.0, first.fHeight - first.fAscent - first.fDescent));
    } else {
        *out_ascent = 0.0f;
        *out_descent = 0.0f;
        *out_leading = 0.0f;
    }

    clear_error();
    return 0;
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
    eink_skia_context *context = as_context(ctx, "eink_skia_draw_text_box");
    if (context == nullptr) {
        return -EINVAL;
    }

    auto paragraph = make_paragraph(context,
                                    "eink_skia_draw_text_box",
                                    utf8,
                                    utf8_len,
                                    family,
                                    size,
                                    weight,
                                    slant,
                                    max_width);
    if (!paragraph) {
        return -EINVAL;
    }

    paragraph->paint(context->canvas, x, y);
    clear_error();
    return 0;
}

int eink_skia_text_cache_stats(void *ctx,
                               int *out_entries,
                               int *out_hits,
                               int *out_misses,
                               int *out_evictions) {
    eink_skia_context *context = as_context(ctx, "eink_skia_text_cache_stats");
    if (context == nullptr) {
        return -EINVAL;
    }
    if (out_entries == nullptr || out_hits == nullptr || out_misses == nullptr || out_evictions == nullptr) {
        return fail_with_code(EINVAL, "eink_skia_text_cache_stats: output pointer is NULL");
    }

    *out_entries = static_cast<int>(context->text_cache.size());
    *out_hits = context->text_cache_hits;
    *out_misses = context->text_cache_misses;
    *out_evictions = context->text_cache_evictions;
    clear_error();
    return 0;
}

int eink_skia_clear_text_cache(void *ctx) {
    eink_skia_context *context = as_context(ctx, "eink_skia_clear_text_cache");
    if (context == nullptr) {
        return -EINVAL;
    }

    context->text_cache.clear();
    context->text_cache_tick = 0;
    context->text_cache_hits = 0;
    context->text_cache_misses = 0;
    context->text_cache_evictions = 0;
    clear_error();
    return 0;
}

int eink_skia_replay_commands(void *ctx,
                              const unsigned char *commands,
                              size_t command_len,
                              int command_count) {
    eink_skia_context *context = as_context(ctx, "eink_skia_replay_commands");
    if (context == nullptr) {
        return -EINVAL;
    }
    if (command_count < 0) {
        return fail_with_code(EINVAL,
                              "eink_skia_replay_commands: invalid command_count=%d",
                              command_count);
    }
    if (command_len > 0 && commands == nullptr) {
        return fail_with_code(EINVAL, "eink_skia_replay_commands: commands is NULL");
    }

    CommandReader reader{commands, command_len, 0};
    int seen = 0;
    while (reader.offset < reader.len) {
        uint8_t opcode = 0;
        if (!read_u8(&reader, &opcode, "opcode")) {
            return -EINVAL;
        }
        ++seen;

        int rv = 0;
        switch (opcode) {
            case CMD_SAVE:
                context->canvas->save();
                break;

            case CMD_RESTORE:
                context->canvas->restore();
                break;

            case CMD_TRANSLATE: {
                float x = 0.0f;
                float y = 0.0f;
                if (!read_f32(&reader, &x, "translate.x") || !read_f32(&reader, &y, "translate.y")) {
                    return -EINVAL;
                }
                context->canvas->translate(x, y);
                break;
            }

            case CMD_SCALE: {
                float sx = 0.0f;
                float sy = 0.0f;
                if (!read_f32(&reader, &sx, "scale.sx") || !read_f32(&reader, &sy, "scale.sy")) {
                    return -EINVAL;
                }
                context->canvas->scale(sx, sy);
                break;
            }

            case CMD_CLIP_RECT: {
                float x = 0.0f;
                float y = 0.0f;
                float width = 0.0f;
                float height = 0.0f;
                rv = replay_rect_args(&reader, "clip-rect", &x, &y, &width, &height);
                if (rv != 0) {
                    return rv;
                }
                context->canvas->clipRect(SkRect::MakeXYWH(x, y, width, height), true);
                break;
            }

            case CMD_SET_COLOR:
                rv = replay_set_color(context, &reader);
                if (rv != 0) {
                    return rv;
                }
                break;

            case CMD_SET_STYLE: {
                int32_t style = 0;
                if (!read_i32(&reader, &style, "set-style")) {
                    return -EINVAL;
                }
                context->paint.setStyle(decode_style(style));
                break;
            }

            case CMD_SET_STROKE_WIDTH: {
                float width = 0.0f;
                if (!read_f32(&reader, &width, "set-stroke-width")) {
                    return -EINVAL;
                }
                if (!(width >= 0.0f)) {
                    return fail_with_code(EINVAL,
                                          "eink_skia_replay_commands: invalid stroke width=%g",
                                          static_cast<double>(width));
                }
                context->paint.setStrokeWidth(width);
                break;
            }

            case CMD_DRAW_RECT: {
                float x = 0.0f;
                float y = 0.0f;
                float width = 0.0f;
                float height = 0.0f;
                rv = replay_rect_args(&reader, "draw-rect", &x, &y, &width, &height);
                if (rv != 0) {
                    return rv;
                }
                context->canvas->drawRect(SkRect::MakeXYWH(x, y, width, height), context->paint);
                break;
            }

            case CMD_DRAW_ROUND_RECT: {
                float x = 0.0f;
                float y = 0.0f;
                float width = 0.0f;
                float height = 0.0f;
                float radius = 0.0f;
                rv = replay_rect_args(&reader, "draw-round-rect", &x, &y, &width, &height);
                if (rv != 0) {
                    return rv;
                }
                if (!read_f32(&reader, &radius, "draw-round-rect.radius")) {
                    return -EINVAL;
                }
                SkScalar r = std::max(0.0f, radius);
                context->canvas->drawRoundRect(SkRect::MakeXYWH(x, y, width, height), r, r, context->paint);
                break;
            }

            case CMD_DRAW_PATH:
                rv = replay_path(context, &reader);
                if (rv != 0) {
                    return rv;
                }
                break;

            case CMD_DRAW_TEXT_BOX:
                rv = replay_text_box(context, &reader);
                if (rv != 0) {
                    return rv;
                }
                break;

            default:
                return fail_with_code(EINVAL,
                                      "eink_skia_replay_commands: unknown opcode=%u at command=%d offset=%zu",
                                      static_cast<unsigned>(opcode),
                                      seen,
                                      reader.offset - 1);
        }
    }

    if (seen != command_count) {
        return fail_with_code(EINVAL,
                              "eink_skia_replay_commands: command_count mismatch expected=%d actual=%d",
                              command_count,
                              seen);
    }

    clear_error();
    return 0;
}

int eink_skia_copy_gray8(void *ctx, unsigned char *dst, size_t dst_len) {
    eink_skia_context *context = as_context(ctx, "eink_skia_copy_gray8");
    if (context == nullptr) {
        return -EINVAL;
    }
    if (dst == nullptr) {
        return fail_with_code(EINVAL, "eink_skia_copy_gray8: dst is NULL");
    }

    size_t required_len = context->pixels.size();
    if (dst_len < required_len) {
        return fail_with_code(EINVAL,
                              "eink_skia_copy_gray8: undersized dst_len=%zu required=%zu",
                              dst_len,
                              required_len);
    }

    std::memcpy(dst, context->pixels.data(), required_len);
    clear_error();
    return 0;
}

int eink_skia_present(void *ctx,
                      int x,
                      int y,
                      int width,
                      int height,
                      int waveform,
                      int flash,
                      int wait) {
    eink_skia_context *context = as_context(ctx, "eink_skia_present");
    if (context == nullptr) {
        return -EINVAL;
    }
    if (width <= 0 || height <= 0) {
        return fail_with_code(EINVAL,
                              "eink_skia_present: invalid present geometry width=%d height=%d",
                              width,
                              height);
    }
    if (width != context->width || height != context->height) {
        return fail_with_code(EINVAL,
                              "eink_skia_present: full-screen present only; requested %dx%d context %dx%d",
                              width,
                              height,
                              context->width,
                              context->height);
    }
    if (x < std::numeric_limits<short>::min() || x > std::numeric_limits<short>::max() ||
        y < std::numeric_limits<short>::min() || y > std::numeric_limits<short>::max()) {
        return fail_with_code(EINVAL, "eink_skia_present: offset out of range x=%d y=%d", x, y);
    }

    int init_rv = ensure_fbink(context);
    if (init_rv != 0) {
        return init_rv;
    }

    FBInkConfig cfg = context->fbink_cfg;
    cfg.wfm_mode = decode_waveform(waveform);
    cfg.is_flashing = flash != 0;
    cfg.ignore_alpha = true;

    const size_t len = context->pixels.size();
    int rv = fbink_print_raw_data(context->fbink_fd,
                                  context->pixels.data(),
                                  context->width,
                                  context->height,
                                  len,
                                  static_cast<short>(x),
                                  static_cast<short>(y),
                                  &cfg);
    if (rv < 0) {
        int saved = errno ? errno : EIO;
        set_error("fbink_print_raw_data failed with rv=%d errno=%d (%s)", rv, saved, strerror(saved));
        return rv;
    }

    if (wait != 0) {
        int wrv = fbink_wait_for_complete(context->fbink_fd, LAST_MARKER);
        if (wrv != EXIT_SUCCESS && wrv != -ENOSYS && wrv != -EINVAL) {
            int saved = errno ? errno : EIO;
            set_error("fbink_wait_for_complete failed with rv=%d errno=%d (%s)", wrv, saved, strerror(saved));
            return wrv;
        }
    }

    context->previous_pixels = context->pixels;
    clear_error();
    return 0;
}
