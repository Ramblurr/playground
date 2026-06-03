#include <cerrno>
#include <climits>
#include <cstdint>
#include <cstring>

#include <janet.h>
#include "fbink.h"

#include "janet_skia_common.hh"
#include "otter_drawing_backend.hh"

namespace {

struct Dimensions {
    int width = otter::kKoboScreenWidth;
    int height = otter::kKoboScreenHeight;
};

void close_or_panic(int fbfd) {
    const int close_rv = fbink_close(fbfd);
    if (close_rv < 0) {
        const int saved = errno;
        janet_panicf("fbink_close failed: rv=%d errno=%d (%s)", close_rv, saved, std::strerror(saved));
    }
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

int present_canvas_to_fbink(const otter::RasterCanvas &canvas, bool flash, bool invert_output, bool night_mode) {
    if (canvas.pixel_format() != otter::PixelFormat::Gray8) {
        janet_panicf("Kobo FBInk presenter currently requires :gray8 canvas, got :%s", otter::pixel_format_name(canvas.pixel_format()));
    }

    FBInkConfig cfg;
    std::memset(&cfg, 0, sizeof(cfg));
    cfg.is_quiet = true;
    cfg.is_flashing = flash;
    cfg.ignore_alpha = true;
    cfg.is_inverted = invert_output;
    cfg.is_nightmode = night_mode;

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
        janet_panic("Skia raster canvas has no pixels to present");
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

static Janet cfun_framebuffer_size(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 0);
    (void) argv;
    const Dimensions dimensions = framebuffer_dimensions();
    return otter::binding::make_dimensions_table(dimensions.width, dimensions.height);
}

static Janet cfun_present(int32_t argc, Janet *argv) {
    janet_arity(argc, 1, 4);
    otter::RasterCanvas *canvas = otter::binding::get_canvas(argv, 0);
    const bool flash = argc >= 2 ? janet_getboolean(argv, 1) : true;
    const bool invert_output = argc >= 3 ? janet_getboolean(argv, 2) : false;
    const bool night_mode = argc >= 4 ? janet_getboolean(argv, 3) : false;
    return janet_wrap_integer(present_canvas_to_fbink(*canvas, flash, invert_output, night_mode));
}

static const JanetReg platform_cfuns[] = {
    {
        "framebuffer-size", cfun_framebuffer_size,
        "(skia/framebuffer-size)\n\n"
        "Return the FBInk framebuffer dimensions."
    },
    {
        "present", cfun_present,
        "(skia/present canvas &opt flash invert-output night-mode)\n\n"
        "Present a gray8 canvas to the Kobo framebuffer with FBInk."
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    otter::binding::register_common_cfuns(env, "skia");
    janet_cfuns(env, "skia", platform_cfuns);
}
