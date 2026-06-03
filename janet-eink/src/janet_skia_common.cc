#include "janet_skia_common.hh"

#include <algorithm>
#include <cmath>
#include <new>
#include <string>
#include <vector>
#include <utility>

namespace otter::binding {
namespace {

static int canvas_gc(void *p, size_t s) {
    (void) s;
    auto *canvas = static_cast<otter::RasterCanvas *>(p);
    canvas->~RasterCanvas();
    return 0;
}

static const JanetAbstractType canvas_type = {
    "otter/skia-canvas",
    canvas_gc,
    nullptr,
    nullptr,
    nullptr,
    JANET_ATEND_PUT
};

static int image_gc(void *p, size_t s) {
    (void) s;
    auto *image = static_cast<otter::RasterImage *>(p);
    image->~RasterImage();
    return 0;
}

static const JanetAbstractType image_type = {
    "otter/skia-image",
    image_gc,
    nullptr,
    nullptr,
    nullptr,
    JANET_ATEND_PUT
};

static int text_line_gc(void *p, size_t s) {
    (void) s;
    auto *line = static_cast<otter::TextLine *>(p);
    line->~TextLine();
    return 0;
}

static const JanetAbstractType text_line_type = {
    "otter/skia-text-line",
    text_line_gc,
    nullptr,
    nullptr,
    nullptr,
    JANET_ATEND_PUT
};

static otter::RasterImage *get_image(Janet *argv, int32_t n) {
    return static_cast<otter::RasterImage *>(janet_getabstract(argv, n, &image_type));
}

static otter::TextLine *get_text_line(Janet *argv, int32_t n) {
    return static_cast<otter::TextLine *>(janet_getabstract(argv, n, &text_line_type));
}

static bool keyword_arg_equals(Janet value, const char *expected) {
    return janet_checktype(value, JANET_KEYWORD) && janet_cstrcmp(janet_unwrap_keyword(value), expected) == 0;
}

static otter::PixelFormat get_pixel_format_value(Janet value) {
    if (keyword_arg_equals(value, "gray8")) {
        return otter::PixelFormat::Gray8;
    }
    if (keyword_arg_equals(value, "rgba32")) {
        return otter::PixelFormat::Rgba32;
    }
    janet_panic("pixel-format must be :gray8 or :rgba32");
}

static Janet pixel_format_keyword(otter::PixelFormat pixel_format) {
    return janet_ckeywordv(otter::pixel_format_name(pixel_format));
}

static Janet cfun_create(int32_t argc, Janet *argv) {
    const Dimensions dimensions = get_dimensions(argc, argv);
    otter::PixelFormat pixel_format = otter::PixelFormat::Gray8;
    int32_t font_arg = 2;
    if (argc >= 3 && (janet_checktype(argv[2], JANET_KEYWORD) || janet_checktype(argv[2], JANET_NIL))) {
        if (!janet_checktype(argv[2], JANET_NIL)) {
            pixel_format = get_pixel_format_value(argv[2]);
        }
        font_arg = 3;
    }
    const char *font_dir = argc > font_arg && !janet_checktype(argv[font_arg], JANET_NIL) ? janet_getcstring(argv, font_arg) : nullptr;
    const char *default_family = argc > font_arg + 1 && !janet_checktype(argv[font_arg + 1], JANET_NIL) ? janet_getcstring(argv, font_arg + 1) : nullptr;
    void *memory = janet_abstract(&canvas_type, sizeof(otter::RasterCanvas));
    auto *canvas = new (memory) otter::RasterCanvas();
    if (!canvas->reset(dimensions.width, dimensions.height, pixel_format, font_dir, default_family)) {
        if (font_dir != nullptr) {
            janet_panicf("Skia raster canvas allocation or font setup failed for %s dimensions %dx%d and font dir %s", otter::pixel_format_name(pixel_format), dimensions.width, dimensions.height, font_dir);
        }
        janet_panicf("Skia raster canvas allocation failed for %s dimensions: %dx%d", otter::pixel_format_name(pixel_format), dimensions.width, dimensions.height);
    }
    return janet_wrap_abstract(canvas);
}

static Janet cfun_clear(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 2);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    otter::clear(*canvas, get_paint(argv, 1));
    return argv[0];
}

static Janet cfun_draw_rect(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 6);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_rect(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)),
            get_paint(argv, 5))) {
        janet_panic("draw-rect requires a positive finite width and height");
    }
    return argv[0];
}

static Janet cfun_draw_rounded_rect(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 7);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_rounded_rect(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)),
            static_cast<float>(janet_getnumber(argv, 5)),
            get_paint(argv, 6))) {
        janet_panic("draw-rounded-rect requires a positive finite width and height and finite radius");
    }
    return argv[0];
}

static std::vector<float> get_radii(Janet *argv, int32_t n) {
    JanetView view = janet_getindexed(argv, n);
    if (view.len != 8) {
        janet_panic("rrect radii must be an array or tuple of 8 numbers");
    }
    std::vector<float> radii;
    radii.reserve(8);
    for (int32_t i = 0; i < view.len; ++i) {
        if (!janet_checktype(view.items[i], JANET_NUMBER)) {
            janet_panic("rrect radii must be an array or tuple of 8 numbers");
        }
        const double value = janet_unwrap_number(view.items[i]);
        if (!std::isfinite(value)) {
            janet_panic("rrect radii must be finite");
        }
        radii.push_back(static_cast<float>(value));
    }
    return radii;
}

static Janet cfun_draw_rrect(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 7);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_rrect(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)),
            get_radii(argv, 5),
            get_paint(argv, 6))) {
        janet_panic("draw-rrect requires a positive finite width and height and eight finite radii");
    }
    return argv[0];
}

static Janet cfun_draw_triangle(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 8);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_triangle(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)),
            static_cast<float>(janet_getnumber(argv, 5)),
            static_cast<float>(janet_getnumber(argv, 6)),
            get_paint(argv, 7))) {
        janet_panic("draw-triangle requires finite points");
    }
    return argv[0];
}

static Janet cfun_draw_circle(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 5);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_circle(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            get_paint(argv, 4))) {
        janet_panic("draw-circle requires a finite center and positive finite radius");
    }
    return argv[0];
}

static Janet cfun_save(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    otter::save(*canvas);
    return argv[0];
}

static Janet cfun_restore(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    if (!otter::restore(*canvas)) {
        janet_panic("cannot restore canvas state below the base save count");
    }
    return argv[0];
}

static Janet cfun_translate(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 3);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    if (!otter::translate(*canvas, static_cast<float>(janet_getnumber(argv, 1)), static_cast<float>(janet_getnumber(argv, 2)))) {
        janet_panic("translate requires finite x and y offsets");
    }
    return argv[0];
}

static Janet cfun_scale(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 3);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    if (!otter::scale(*canvas, static_cast<float>(janet_getnumber(argv, 1)), static_cast<float>(janet_getnumber(argv, 2)))) {
        janet_panic("scale requires finite sx and sy values");
    }
    return argv[0];
}

static Janet cfun_clip_rect(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 5);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    if (!otter::clip_rect(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)))) {
        janet_panic("clip-rect requires finite coordinates and positive finite width and height");
    }
    return argv[0];
}

static Janet cfun_draw_line(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 6);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_line(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)),
            get_paint(argv, 5))) {
        janet_panic("draw-line requires finite points and positive finite stroke width");
    }
    return argv[0];
}

static Janet cfun_draw_path(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 4);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    JanetView view = janet_getindexed(argv, 1);
    std::vector<float> coords;
    coords.reserve(static_cast<std::size_t>(view.len));
    for (int32_t i = 0; i < view.len; ++i) {
        coords.push_back(static_cast<float>(janet_getnumber(view.items, i)));
    }
    const bool closed = janet_getboolean(argv, 2);
    if (!otter::draw_path(*canvas, coords, closed, get_paint(argv, 3))) {
        janet_panic("draw-path requires at least two finite coordinate pairs");
    }
    return argv[0];
}

static Janet cfun_load_png(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    const char *path = janet_getcstring(argv, 0);
    void *memory = janet_abstract(&image_type, sizeof(otter::RasterImage));
    auto *image = new (memory) otter::RasterImage();
    if (!image->load_png(path)) {
        janet_panicf("failed to load PNG image: %s", path);
    }
    return janet_wrap_abstract(image);
}

static Janet cfun_image_width(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    return janet_wrap_integer(get_image(argv, 0)->width());
}

static Janet cfun_image_height(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    return janet_wrap_integer(get_image(argv, 0)->height());
}

static Janet cfun_draw_image(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 11);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    otter::RasterImage *image = get_image(argv, 1);
    if (!otter::draw_image(
            *canvas,
            *image,
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)),
            static_cast<float>(janet_getnumber(argv, 5)),
            static_cast<float>(janet_getnumber(argv, 6)),
            static_cast<float>(janet_getnumber(argv, 7)),
            static_cast<float>(janet_getnumber(argv, 8)),
            static_cast<float>(janet_getnumber(argv, 9)),
            static_cast<float>(janet_getnumber(argv, 10)))) {
        janet_panic("draw-image requires finite source and destination rectangles within image bounds");
    }
    return argv[0];
}

static Janet cfun_sample_gray(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 3);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    const int x = janet_getinteger(argv, 1);
    const int y = janet_getinteger(argv, 2);
    if (x < 0 || y < 0 || x >= canvas->width() || y >= canvas->height()) {
        janet_panicf("sample-gray coordinates out of bounds: %d,%d for %dx%d", x, y, canvas->width(), canvas->height());
    }
    return janet_wrap_integer(otter::sample_gray(*canvas, x, y));
}

Janet make_rgba_table(const otter::RgbaPixel &pixel) {
    JanetTable *table = janet_table(4);
    janet_table_put(table, janet_ckeywordv("r"), janet_wrap_integer(pixel.r));
    janet_table_put(table, janet_ckeywordv("g"), janet_wrap_integer(pixel.g));
    janet_table_put(table, janet_ckeywordv("b"), janet_wrap_integer(pixel.b));
    janet_table_put(table, janet_ckeywordv("a"), janet_wrap_integer(pixel.a));
    return janet_wrap_table(table);
}

static Janet cfun_sample_rgba(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 3);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    const int x = janet_getinteger(argv, 1);
    const int y = janet_getinteger(argv, 2);
    if (x < 0 || y < 0 || x >= canvas->width() || y >= canvas->height()) {
        janet_panicf("sample-rgba coordinates out of bounds: %d,%d for %dx%d", x, y, canvas->width(), canvas->height());
    }
    return make_rgba_table(otter::sample_rgba(*canvas, x, y));
}

static Janet cfun_canvas_info(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    JanetTable *table = janet_table(3);
    janet_table_put(table, janet_ckeywordv("width"), janet_wrap_integer(canvas->width()));
    janet_table_put(table, janet_ckeywordv("height"), janet_wrap_integer(canvas->height()));
    janet_table_put(table, janet_ckeywordv("pixel-format"), pixel_format_keyword(canvas->pixel_format()));
    return janet_wrap_table(table);
}

static Janet cfun_stats(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    return make_stats_table(otter::compute_stats(*canvas));
}

Janet make_text_line_metrics_table(const otter::TextLineMetrics &metrics) {
    JanetTable *table = janet_table(2);
    janet_table_put(table, janet_ckeywordv("width"), janet_wrap_number(metrics.width));
    janet_table_put(table, janet_ckeywordv("height"), janet_wrap_number(metrics.height));
    return janet_wrap_table(table);
}

std::string get_text_string(Janet *argv, int32_t n) {
    JanetByteView view = janet_getbytes(argv, n);
    return std::string(reinterpret_cast<const char *>(view.bytes), static_cast<std::size_t>(view.len));
}

static Janet cfun_shape_text(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 8);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    const std::string text = get_text_string(argv, 1);
    otter::FontOptions options;
    const char *family = janet_getcstring(argv, 2);
    options.family = family != nullptr ? family : "";
    options.size = static_cast<float>(janet_getnumber(argv, 3));
    options.weight = janet_getinteger(argv, 4);
    options.width = janet_getinteger(argv, 5);
    options.slant = janet_getinteger(argv, 6);
    const char *features = janet_getcstring(argv, 7);
    otter::TextLine shaped;
    std::string error_message;
    if (!otter::shape_text(*canvas, text, options, features != nullptr ? features : "", &shaped, &error_message)) {
        janet_panic(error_message.empty() ? "shape-text failed" : error_message.c_str());
    }
    void *memory = janet_abstract(&text_line_type, sizeof(otter::TextLine));
    auto *line = new (memory) otter::TextLine(std::move(shaped));
    return janet_wrap_abstract(line);
}

static Janet cfun_text_line_metrics(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    otter::TextLine *line = get_text_line(argv, 0);
    return make_text_line_metrics_table(line->metrics);
}

static Janet cfun_draw_text_line(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 5);
    otter::RasterCanvas *canvas = get_canvas(argv, 0);
    otter::TextLine *line = get_text_line(argv, 1);
    const float x = static_cast<float>(janet_getnumber(argv, 2));
    const float y = static_cast<float>(janet_getnumber(argv, 3));
    if (!otter::draw_text_line(*canvas, *line, x, y, get_paint(argv, 4))) {
        janet_panic("draw-text-line requires finite coordinates and a non-empty shaped text line");
    }
    return argv[0];
}

static const JanetReg common_cfuns[] = {
    {
        "create", cfun_create,
        "(skia/create &opt width height pixel-format font-dir default-family)\n\n"
        "Create a raster Skia canvas in :gray8 or :rgba32 format."
    },
    {
        "clear", cfun_clear,
        "(skia/clear canvas paint)\n\n"
        "Fill a raster canvas with a normalized paint."
    },
    {
        "draw-rect", cfun_draw_rect,
        "(skia/draw-rect canvas x y width height paint)\n\n"
        "Draw a rectangle on a raster canvas."
    },
    {
        "draw-rounded-rect", cfun_draw_rounded_rect,
        "(skia/draw-rounded-rect canvas x y width height radius paint)\n\n"
        "Draw a rounded rectangle on a raster canvas."
    },
    {
        "draw-rrect", cfun_draw_rrect,
        "(skia/draw-rrect canvas x y width height radii paint)\n\n"
        "Draw a rounded rectangle with per-corner radii on a raster canvas."
    },
    {
        "draw-triangle", cfun_draw_triangle,
        "(skia/draw-triangle canvas x1 y1 x2 y2 x3 y3 paint)\n\n"
        "Draw a triangle on a raster canvas."
    },
    {
        "draw-circle", cfun_draw_circle,
        "(skia/draw-circle canvas cx cy radius paint)\n\n"
        "Draw a circle on a raster canvas."
    },
    {
        "save", cfun_save,
        "(skia/save canvas)\n\nSave the current canvas transform and clip state."
    },
    {
        "restore", cfun_restore,
        "(skia/restore canvas)\n\nRestore the previous canvas transform and clip state."
    },
    {
        "translate", cfun_translate,
        "(skia/translate canvas x y)\n\nTranslate future draw operations."
    },
    {
        "scale", cfun_scale,
        "(skia/scale canvas sx sy)\n\nScale future draw operations."
    },
    {
        "clip-rect", cfun_clip_rect,
        "(skia/clip-rect canvas x y width height)\n\nIntersect the current clip with a rectangle."
    },
    {
        "draw-line", cfun_draw_line,
        "(skia/draw-line canvas x1 y1 x2 y2 paint)\n\nDraw a stroked line on a raster canvas."
    },
    {
        "draw-path", cfun_draw_path,
        "(skia/draw-path canvas coords closed? paint)\n\nDraw a path from flattened coordinates."
    },
    {
        "load-png", cfun_load_png,
        "(skia/load-png path)\n\nLoad a PNG file and return an image handle."
    },
    {
        "image-width", cfun_image_width,
        "(skia/image-width image)\n\nReturn image width in pixels."
    },
    {
        "image-height", cfun_image_height,
        "(skia/image-height image)\n\nReturn image height in pixels."
    },
    {
        "draw-image", cfun_draw_image,
        "(skia/draw-image canvas image src-x src-y src-width src-height dst-x dst-y dst-width dst-height alpha)\n\nDraw a source rectangle from an image into a canvas."
    },
    {
        "shape-text", cfun_shape_text,
        "(skia/shape-text canvas text family size weight width slant features)\n\nShape a single text line and return a native text-line handle."
    },
    {
        "text-line-metrics", cfun_text_line_metrics,
        "(skia/text-line-metrics text-line)\n\nReturn shaped text-line cap-height metrics."
    },
    {
        "draw-text-line", cfun_draw_text_line,
        "(skia/draw-text-line canvas text-line x y paint)\n\nDraw a shaped text line."
    },
    {
        "sample-gray", cfun_sample_gray,
        "(skia/sample-gray canvas x y)\n\n"
        "Return the gray value at a canvas pixel."
    },
    {
        "sample-rgba", cfun_sample_rgba,
        "(skia/sample-rgba canvas x y)\n\nReturn the RGBA value at a canvas pixel."
    },
    {
        "canvas-info", cfun_canvas_info,
        "(skia/canvas-info canvas)\n\nReturn raster canvas width, height, and pixel format."
    },
    {
        "stats", cfun_stats,
        "(skia/stats canvas)\n\n"
        "Return raster canvas statistics."
    },
    {NULL, NULL, NULL}
};

}  // namespace

Dimensions get_dimensions(int32_t argc, Janet *argv) {
    janet_arity(argc, 0, 5);
    Dimensions dimensions;
    if (argc >= 1) {
        dimensions.width = janet_getinteger(argv, 0);
    }
    if (argc >= 2) {
        dimensions.height = janet_getinteger(argv, 1);
    }
    if (!otter::valid_dimensions(dimensions.width, dimensions.height)) {
        janet_panicf("invalid canvas dimensions: %dx%d", dimensions.width, dimensions.height);
    }
    return dimensions;
}

otter::RasterCanvas *get_canvas(Janet *argv, int32_t n) {
    return static_cast<otter::RasterCanvas *>(janet_getabstract(argv, n, &canvas_type));
}

bool keyword_equals(Janet value, const char *expected) {
    return janet_checktype(value, JANET_KEYWORD) && janet_cstrcmp(janet_unwrap_keyword(value), expected) == 0;
}

Janet paint_field(Janet paint, const char *key) {
    Janet value = janet_get(paint, janet_ckeywordv(key));
    if (janet_checktype(value, JANET_NIL)) {
        janet_panicf("paint missing required field :%s", key);
    }
    return value;
}

float number_field(Janet paint, const char *key, float default_value, bool required) {
    Janet value = janet_get(paint, janet_ckeywordv(key));
    if (janet_checktype(value, JANET_NIL)) {
        if (required) {
            janet_panicf("paint missing required number field :%s", key);
        }
        return default_value;
    }
    if (!janet_checktype(value, JANET_NUMBER)) {
        janet_panicf("paint field :%s must be a number", key);
    }
    const double number = janet_unwrap_number(value);
    if (!std::isfinite(number)) {
        janet_panicf("paint field :%s must be finite", key);
    }
    return static_cast<float>(number);
}

bool bool_field(Janet paint, const char *key, bool default_value) {
    Janet value = janet_get(paint, janet_ckeywordv(key));
    return janet_checktype(value, JANET_NIL) ? default_value : janet_truthy(value);
}

otter::PaintCap cap_field(Janet paint) {
    Janet value = janet_get(paint, janet_ckeywordv("cap"));
    if (janet_checktype(value, JANET_NIL) || keyword_equals(value, "butt")) {
        return otter::PaintCap::Butt;
    }
    if (keyword_equals(value, "round")) {
        return otter::PaintCap::Round;
    }
    if (keyword_equals(value, "square")) {
        return otter::PaintCap::Square;
    }
    janet_panic("paint field :cap must be :butt, :round, or :square");
}

otter::PaintJoin join_field(Janet paint) {
    Janet value = janet_get(paint, janet_ckeywordv("join"));
    if (janet_checktype(value, JANET_NIL) || keyword_equals(value, "miter")) {
        return otter::PaintJoin::Miter;
    }
    if (keyword_equals(value, "round")) {
        return otter::PaintJoin::Round;
    }
    if (keyword_equals(value, "bevel")) {
        return otter::PaintJoin::Bevel;
    }
    janet_panic("paint field :join must be :miter, :round, or :bevel");
}

otter::NormalizedPaint get_paint(Janet *argv, int32_t n) {
    Janet value = argv[n];
    if (!janet_checktype(value, JANET_TABLE) && !janet_checktype(value, JANET_STRUCT)) {
        janet_panic("paint must be a table or struct normalized by lib/paint.janet");
    }

    otter::NormalizedPaint paint;
    Janet style = paint_field(value, "style");
    if (keyword_equals(style, "fill")) {
        paint.style = otter::PaintStyle::Fill;
    } else if (keyword_equals(style, "stroke")) {
        paint.style = otter::PaintStyle::Stroke;
    } else {
        janet_panic("paint field :style must be :fill or :stroke");
    }

    paint.r = std::clamp(number_field(value, "r", 0.0f, true), 0.0f, 1.0f);
    paint.g = std::clamp(number_field(value, "g", 0.0f, true), 0.0f, 1.0f);
    paint.b = std::clamp(number_field(value, "b", 0.0f, true), 0.0f, 1.0f);
    paint.a = std::clamp(number_field(value, "a", 1.0f, true), 0.0f, 1.0f);
    paint.anti_alias = bool_field(value, "anti-alias?", true);
    paint.skia_dither = bool_field(value, "skia-dither?", false);

    if (paint.style == otter::PaintStyle::Stroke) {
        paint.stroke_width = number_field(value, "width", 1.0f, false);
        if (paint.stroke_width <= 0.0f) {
            janet_panic("paint field :width must be positive");
        }
        paint.cap = cap_field(value);
        paint.join = join_field(value);
        paint.miter = number_field(value, "miter", 4.0f, false);
        if (paint.miter <= 0.0f) {
            janet_panic("paint field :miter must be positive");
        }
    }
    return paint;
}

Janet make_stats_table(const otter::CanvasStats &stats) {
    JanetTable *table = janet_table(8);
    janet_table_put(table, janet_ckeywordv("width"), janet_wrap_integer(stats.width));
    janet_table_put(table, janet_ckeywordv("height"), janet_wrap_integer(stats.height));
    janet_table_put(table, janet_ckeywordv("pixel-format"), janet_ckeywordv(otter::pixel_format_name(stats.pixel_format)));
    janet_table_put(table, janet_ckeywordv("min-gray"), janet_wrap_integer(stats.min_gray));
    janet_table_put(table, janet_ckeywordv("max-gray"), janet_wrap_integer(stats.max_gray));
    janet_table_put(table, janet_ckeywordv("gray-shades"), janet_wrap_integer(stats.gray_shades));
    janet_table_put(table, janet_ckeywordv("non-white-pixels"), janet_wrap_integer(stats.non_white_pixels));
    janet_table_put(table, janet_ckeywordv("checksum"), janet_wrap_number(static_cast<double>(stats.checksum)));
    return janet_wrap_table(table);
}

Janet make_dimensions_table(int width, int height) {
    JanetTable *table = janet_table(2);
    janet_table_put(table, janet_ckeywordv("width"), janet_wrap_integer(width));
    janet_table_put(table, janet_ckeywordv("height"), janet_wrap_integer(height));
    return janet_wrap_table(table);
}

void register_common_cfuns(JanetTable *env, const char *prefix) {
    janet_cfuns(env, prefix, common_cfuns);
}

}  // namespace otter::binding
