#include <cerrno>
#include <climits>
#include <cstdint>
#include <cstring>
#include <new>

#include <janet.h>
#include "fbink.h"

#include "otter_drawing_backend.hh"

namespace {

struct Dimensions {
    int width = otter::kKoboScreenWidth;
    int height = otter::kKoboScreenHeight;
};

using NativeCanvas = otter::GrayCanvas;

static int canvas_gc(void *p, size_t s) {
    (void) s;
    auto *canvas = static_cast<NativeCanvas *>(p);
    canvas->~NativeCanvas();
    return 0;
}

static const JanetAbstractType canvas_type = {
    "otter/gray-canvas",
    canvas_gc,
    nullptr,
    nullptr,
    nullptr,
    JANET_ATEND_PUT
};

void close_or_panic(int fbfd) {
    const int close_rv = fbink_close(fbfd);
    if (close_rv < 0) {
        const int saved = errno;
        janet_panicf("fbink_close failed: rv=%d errno=%d (%s)", close_rv, saved, std::strerror(saved));
    }
}

NativeCanvas *get_canvas(Janet *argv, int32_t n) {
    return static_cast<NativeCanvas *>(janet_getabstract(argv, n, &canvas_type));
}

uint8_t get_gray(Janet *argv, int32_t n) {
    const int gray = janet_getinteger(argv, n);
    if (gray < 0 || gray > 255) {
        janet_panicf("gray value out of range 0..255: %d", gray);
    }
    return static_cast<uint8_t>(gray);
}

Dimensions get_dimensions(int32_t argc, Janet *argv) {
    janet_arity(argc, 0, 2);
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

Janet make_dimensions_table(const Dimensions &dimensions) {
    JanetTable *table = janet_table(2);
    janet_table_put(table, janet_ckeywordv("width"), janet_wrap_integer(dimensions.width));
    janet_table_put(table, janet_ckeywordv("height"), janet_wrap_integer(dimensions.height));
    return janet_wrap_table(table);
}

Dimensions framebuffer_dimensions() {
    FBInkConfig cfg;
    std::memset(&cfg, 0, sizeof(cfg));
    cfg.is_quiet = true;
    cfg.ignore_alpha = true;

    const int fbfd = fbink_open();
    if (fbfd < 0) {
        janet_panicf("fbink_open failed: errno=%d (%s)", errno, std::strerror(errno));
    }

    int rv = fbink_init(fbfd, &cfg);
    if (rv < 0) {
        const int saved = errno;
        fbink_close(fbfd);
        janet_panicf("fbink_init failed: rv=%d errno=%d (%s)", rv, saved, std::strerror(saved));
    }

    FBInkState state;
    std::memset(&state, 0, sizeof(state));
    fbink_get_state(&cfg, &state);

    const uint32_t target_width = state.view_width != 0 ? state.view_width : state.screen_width;
    const uint32_t target_height = state.view_height != 0 ? state.view_height : state.screen_height;
    if (target_width == 0 || target_height == 0 || target_width > INT_MAX || target_height > INT_MAX) {
        fbink_close(fbfd);
        janet_panicf("unsupported framebuffer dimensions: %ux%u", target_width, target_height);
    }

    close_or_panic(fbfd);
    return Dimensions{static_cast<int>(target_width), static_cast<int>(target_height)};
}

int present_canvas_to_fbink(const NativeCanvas &canvas, bool flash) {
    FBInkConfig cfg;
    std::memset(&cfg, 0, sizeof(cfg));
    cfg.is_quiet = true;
    cfg.is_flashing = flash;
    cfg.ignore_alpha = true;

    const int fbfd = fbink_open();
    if (fbfd < 0) {
        janet_panicf("fbink_open failed: errno=%d (%s)", errno, std::strerror(errno));
    }

    int rv = fbink_init(fbfd, &cfg);
    if (rv < 0) {
        const int saved = errno;
        fbink_close(fbfd);
        janet_panicf("fbink_init failed: rv=%d errno=%d (%s)", rv, saved, std::strerror(saved));
    }

    const void *pixels = canvas.bitmap().getPixels();
    const size_t byte_count = static_cast<size_t>(canvas.width()) * static_cast<size_t>(canvas.height());
    if (pixels == nullptr || byte_count == 0) {
        fbink_close(fbfd);
        janet_panic("Skia gray8 canvas has no pixels to present");
    }

    rv = fbink_print_raw_data(
        fbfd,
        static_cast<const unsigned char *>(pixels),
        canvas.width(),
        canvas.height(),
        byte_count,
        0,
        0,
        &cfg);
    if (rv < 0) {
        const int saved = errno;
        fbink_close(fbfd);
        janet_panicf("fbink_print_raw_data failed: rv=%d errno=%d (%s)", rv, saved, std::strerror(saved));
    }

    close_or_panic(fbfd);
    return rv;
}

}  // namespace

static Janet cfun_create(int32_t argc, Janet *argv) {
    const Dimensions dimensions = get_dimensions(argc, argv);
    void *memory = janet_abstract(&canvas_type, sizeof(NativeCanvas));
    auto *canvas = new (memory) NativeCanvas();
    if (!canvas->reset(dimensions.width, dimensions.height)) {
        canvas->~NativeCanvas();
        janet_panicf("Skia gray8 canvas allocation failed for dimensions: %dx%d", dimensions.width, dimensions.height);
    }
    return janet_wrap_abstract(canvas);
}

static Janet cfun_clear(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 2);
    NativeCanvas *canvas = get_canvas(argv, 0);
    otter::clear(*canvas, get_gray(argv, 1));
    return argv[0];
}

static Janet cfun_draw_rect(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 6);
    NativeCanvas *canvas = get_canvas(argv, 0);
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

static Janet cfun_draw_round_rect(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 7);
    NativeCanvas *canvas = get_canvas(argv, 0);
    if (!otter::draw_round_rect(
            *canvas,
            static_cast<float>(janet_getnumber(argv, 1)),
            static_cast<float>(janet_getnumber(argv, 2)),
            static_cast<float>(janet_getnumber(argv, 3)),
            static_cast<float>(janet_getnumber(argv, 4)),
            static_cast<float>(janet_getnumber(argv, 5)),
            get_gray(argv, 6))) {
        janet_panic("draw-round-rect requires a positive finite width and height and finite radius");
    }
    return argv[0];
}

static Janet cfun_draw_triangle(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 8);
    NativeCanvas *canvas = get_canvas(argv, 0);
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
    NativeCanvas *canvas = get_canvas(argv, 0);
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

static Janet cfun_sample_gray(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 3);
    NativeCanvas *canvas = get_canvas(argv, 0);
    const int x = janet_getinteger(argv, 1);
    const int y = janet_getinteger(argv, 2);
    if (x < 0 || y < 0 || x >= canvas->width() || y >= canvas->height()) {
        janet_panicf("sample-gray coordinates out of bounds: %d,%d for %dx%d", x, y, canvas->width(), canvas->height());
    }
    return janet_wrap_integer(otter::sample_gray(*canvas, x, y));
}

static Janet cfun_stats(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    NativeCanvas *canvas = get_canvas(argv, 0);
    return make_stats_table(otter::compute_stats(*canvas));
}

static Janet cfun_self_test(int32_t argc, Janet *argv) {
    const Dimensions dimensions = get_dimensions(argc, argv);
    NativeCanvas canvas;
    otter::GrayStats stats;
    if (!otter::render_demo_scene(dimensions.width, dimensions.height, &canvas, &stats)) {
        janet_panicf("Skia demo render allocation failed for dimensions: %dx%d", dimensions.width, dimensions.height);
    }
    return make_stats_table(stats);
}

static Janet cfun_framebuffer_size(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 0);
    (void) argv;
    return make_dimensions_table(framebuffer_dimensions());
}

static Janet cfun_present(int32_t argc, Janet *argv) {
    janet_arity(argc, 1, 2);
    NativeCanvas *canvas = get_canvas(argv, 0);
    const bool flash = argc >= 2 ? janet_getboolean(argv, 1) : true;
    return janet_wrap_integer(present_canvas_to_fbink(*canvas, flash));
}

static Janet cfun_present_demo(int32_t argc, Janet *argv) {
    janet_arity(argc, 0, 1);
    const bool flash = argc >= 1 ? janet_getboolean(argv, 0) : true;
    const Dimensions dimensions = framebuffer_dimensions();

    NativeCanvas canvas;
    otter::GrayStats stats;
    if (!otter::render_demo_scene(dimensions.width, dimensions.height, &canvas, &stats)) {
        janet_panicf("Skia demo render allocation failed for framebuffer dimensions: %dx%d", dimensions.width, dimensions.height);
    }

    const int rv = present_canvas_to_fbink(canvas, flash);
    Janet result = make_stats_table(stats);
    janet_table_put(janet_unwrap_table(result), janet_ckeywordv("present-result"), janet_wrap_integer(rv));
    return result;
}

static const JanetReg cfuns[] = {
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
        "draw-round-rect", cfun_draw_round_rect,
        "(skia/draw-round-rect canvas x y width height radius gray)\n\n"
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
        "sample-gray", cfun_sample_gray,
        "(skia/sample-gray canvas x y)\n\n"
        "Return the gray value at a canvas pixel."
    },
    {
        "stats", cfun_stats,
        "(skia/stats canvas)\n\n"
        "Return gray8 canvas statistics."
    },
    {
        "self-test", cfun_self_test,
        "(skia/self-test &opt width height)\n\n"
        "Render the gray shape demo off-screen and return render statistics."
    },
    {
        "framebuffer-size", cfun_framebuffer_size,
        "(skia/framebuffer-size)\n\n"
        "Return the FBInk framebuffer dimensions."
    },
    {
        "present", cfun_present,
        "(skia/present canvas &opt flash)\n\n"
        "Present a gray8 canvas to the Kobo framebuffer with FBInk."
    },
    {
        "present-demo", cfun_present_demo,
        "(skia/present-demo &opt flash)\n\n"
        "Render and present the gray shape demo to the Kobo framebuffer with FBInk."
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    janet_cfuns(env, "skia", cfuns);
}
