#include "janet_skia_common.hh"

#include <new>
#include <string>
#include <vector>

namespace otter::binding {
namespace {

static int canvas_gc(void *p, size_t s) {
    (void) s;
    auto *canvas = static_cast<otter::GrayCanvas *>(p);
    canvas->~GrayCanvas();
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

static otter::RasterImage *get_image(Janet *argv, int32_t n) {
    return static_cast<otter::RasterImage *>(janet_getabstract(argv, n, &image_type));
}

static Janet cfun_create(int32_t argc, Janet *argv) {
    const Dimensions dimensions = get_dimensions(argc, argv);
    const char *font_dir = argc >= 3 && !janet_checktype(argv[2], JANET_NIL) ? janet_getcstring(argv, 2) : nullptr;
    const char *default_family = argc >= 4 && !janet_checktype(argv[3], JANET_NIL) ? janet_getcstring(argv, 3) : nullptr;
    void *memory = janet_abstract(&canvas_type, sizeof(otter::GrayCanvas));
    auto *canvas = new (memory) otter::GrayCanvas();
    if (!canvas->reset(dimensions.width, dimensions.height, font_dir, default_family)) {
        canvas->~GrayCanvas();
        if (font_dir != nullptr) {
            janet_panicf("Skia gray8 canvas allocation or font setup failed for dimensions %dx%d and font dir %s", dimensions.width, dimensions.height, font_dir);
        }
        janet_panicf("Skia gray8 canvas allocation failed for dimensions: %dx%d", dimensions.width, dimensions.height);
    }
    return janet_wrap_abstract(canvas);
}

static Janet cfun_clear(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 2);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    otter::clear(*canvas, get_gray(argv, 1));
    return argv[0];
}

static Janet cfun_draw_rect(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 6);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_rect(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)),
            get_gray(argv, 5))) {
        janet_panic("draw-rect requires a positive finite width and height");
    }
    return argv[0];
}

static Janet cfun_draw_rounded_rect(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 7);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_rounded_rect(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)),
            static_cast<float>(janet_getnumber(argv, 5)),
            get_gray(argv, 6))) {
        janet_panic("draw-rounded-rect requires a positive finite width and height and finite radius");
    }
    return argv[0];
}

static Janet cfun_draw_triangle(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 8);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_triangle(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)),
            static_cast<float>(janet_getnumber(argv, 5)),
            static_cast<float>(janet_getnumber(argv, 6)),
            get_gray(argv, 7))) {
        janet_panic("draw-triangle requires finite points");
    }
    return argv[0];
}

static Janet cfun_draw_circle(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 5);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_circle(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            get_gray(argv, 4))) {
        janet_panic("draw-circle requires a finite center and positive finite radius");
    }
    return argv[0];
}

static Janet cfun_save(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    otter::save(*canvas);
    return argv[0];
}

static Janet cfun_restore(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    if (!otter::restore(*canvas)) {
        janet_panic("cannot restore canvas state below the base save count");
    }
    return argv[0];
}

static Janet cfun_translate(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 3);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    if (!otter::translate(*canvas, static_cast<float>(janet_getnumber(argv, 1)), static_cast<float>(janet_getnumber(argv, 2)))) {
        janet_panic("translate requires finite x and y offsets");
    }
    return argv[0];
}

static Janet cfun_scale(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 3);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    if (!otter::scale(*canvas, static_cast<float>(janet_getnumber(argv, 1)), static_cast<float>(janet_getnumber(argv, 2)))) {
        janet_panic("scale requires finite sx and sy values");
    }
    return argv[0];
}

static Janet cfun_clip_rect(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 5);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
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
    janet_fixarity(argc, 7);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_line(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)),
            get_gray(argv, 5),
            static_cast<float>(janet_getnumber(argv, 6)))) {
        janet_panic("draw-line requires finite points and positive finite stroke width");
    }
    return argv[0];
}

static Janet cfun_draw_path(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 4);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    JanetView view = janet_getindexed(argv, 1);
    std::vector<float> coords;
    coords.reserve(static_cast<std::size_t>(view.len));
    for (int32_t i = 0; i < view.len; ++i) {
        coords.push_back(static_cast<float>(janet_getnumber(view.items, i)));
    }
    const bool closed = janet_getboolean(argv, 2);
    if (!otter::draw_path(*canvas, coords, closed, get_gray(argv, 3))) {
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
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
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
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    const int x = janet_getinteger(argv, 1);
    const int y = janet_getinteger(argv, 2);
    if (x < 0 || y < 0 || x >= canvas->width() || y >= canvas->height()) {
        janet_panicf("sample-gray coordinates out of bounds: %d,%d for %dx%d", x, y, canvas->width(), canvas->height());
    }
    return janet_wrap_integer(otter::sample_gray(*canvas, x, y));
}

static Janet cfun_stats(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    return make_stats_table(otter::compute_stats(*canvas));
}

Janet make_text_metrics_table(const otter::TextMetrics &metrics) {
    JanetTable *table = janet_table(5);
    janet_table_put(table, janet_ckeywordv("width"), janet_wrap_number(metrics.width));
    janet_table_put(table, janet_ckeywordv("height"), janet_wrap_number(metrics.height));
    janet_table_put(table, janet_ckeywordv("ascent"), janet_wrap_number(metrics.ascent));
    janet_table_put(table, janet_ckeywordv("descent"), janet_wrap_number(metrics.descent));
    janet_table_put(table, janet_ckeywordv("baseline"), janet_wrap_number(metrics.baseline));
    return janet_wrap_table(table);
}

std::string get_text_string(Janet *argv, int32_t n) {
    JanetByteView view = janet_getbytes(argv, n);
    return std::string(reinterpret_cast<const char *>(view.bytes), static_cast<std::size_t>(view.len));
}

static Janet cfun_measure_text(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 5);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    const std::string text = get_text_string(argv, 1);
    const char *family = janet_getcstring(argv, 2);
    const float size = static_cast<float>(janet_getnumber(argv, 3));
    const int weight = janet_getinteger(argv, 4);
    otter::TextMetrics metrics;
    if (!otter::measure_text(*canvas, text, family != nullptr ? family : "", size, weight, &metrics)) {
        janet_panic("measure-text requires a canvas created with a valid font directory and positive text size");
    }
    return make_text_metrics_table(metrics);
}

static Janet cfun_draw_text(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 8);
    otter::GrayCanvas *canvas = get_canvas(argv, 0);
    const std::string text = get_text_string(argv, 1);
    const float x = static_cast<float>(janet_getnumber(argv, 2));
    const float y = static_cast<float>(janet_getnumber(argv, 3));
    const char *family = janet_getcstring(argv, 4);
    const float size = static_cast<float>(janet_getnumber(argv, 5));
    const int weight = janet_getinteger(argv, 6);
    if (!otter::draw_text(*canvas, text, x, y, family != nullptr ? family : "", size, weight, get_gray(argv, 7))) {
        janet_panic("draw-text requires finite coordinates, a canvas created with a valid font directory, and positive text size");
    }
    return argv[0];
}

static const JanetReg common_cfuns[] = {
    {
        "create", cfun_create,
        "(skia/create &opt width height)\n\n"
        "Create a gray8 Skia canvas."
    },
    {
        "clear", cfun_clear,
        "(skia/clear canvas gray)\n\n"
        "Fill a gray8 canvas with a gray value in 0..255."
    },
    {
        "draw-rect", cfun_draw_rect,
        "(skia/draw-rect canvas x y width height gray)\n\n"
        "Draw a filled rectangle on a gray8 canvas."
    },
    {
        "draw-rounded-rect", cfun_draw_rounded_rect,
        "(skia/draw-rounded-rect canvas x y width height radius gray)\n\n"
        "Draw a filled rounded rectangle on a gray8 canvas."
    },
    {
        "draw-triangle", cfun_draw_triangle,
        "(skia/draw-triangle canvas x1 y1 x2 y2 x3 y3 gray)\n\n"
        "Draw a filled triangle on a gray8 canvas."
    },
    {
        "draw-circle", cfun_draw_circle,
        "(skia/draw-circle canvas cx cy radius gray)\n\n"
        "Draw a filled circle on a gray8 canvas."
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
        "(skia/draw-line canvas x1 y1 x2 y2 gray stroke-width)\n\nDraw a stroked line on a gray8 canvas."
    },
    {
        "draw-path", cfun_draw_path,
        "(skia/draw-path canvas coords closed? gray)\n\nDraw a filled path from flattened coordinates."
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
        "measure-text", cfun_measure_text,
        "(skia/measure-text canvas text family size weight)\n\nMeasure a single-line label."
    },
    {
        "draw-text", cfun_draw_text,
        "(skia/draw-text canvas text x y family size weight gray)\n\nDraw a single-line label."
    },
    {
        "sample-gray", cfun_sample_gray,
        "(skia/sample-gray canvas x y)\n\n"
        "Return the gray value at a canvas pixel."
    },
    {
        "stats", cfun_stats,
        "(skia/stats canvas)\n\n"
        "Return gray8 canvas statistics."
    },
    {NULL, NULL, NULL}
};

}  // namespace

Dimensions get_dimensions(int32_t argc, Janet *argv) {
    janet_arity(argc, 0, 4);
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

otter::GrayCanvas *get_canvas(Janet *argv, int32_t n) {
    return static_cast<otter::GrayCanvas *>(janet_getabstract(argv, n, &canvas_type));
}

std::uint8_t get_gray(Janet *argv, int32_t n) {
    const int gray = janet_getinteger(argv, n);
    if (gray < 0 || gray > 255) {
        janet_panicf("gray value out of range 0..255: %d", gray);
    }
    return static_cast<std::uint8_t>(gray);
}

Janet make_stats_table(const otter::GrayStats &stats) {
    JanetTable *table = janet_table(8);
    janet_table_put(table, janet_ckeywordv("width"), janet_wrap_integer(stats.width));
    janet_table_put(table, janet_ckeywordv("height"), janet_wrap_integer(stats.height));
    janet_table_put(table, janet_ckeywordv("pixel-format"), janet_ckeywordv("gray8"));
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
