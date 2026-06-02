#include <cerrno>
#include <climits>
#include <cstddef>
#include <cstring>

#include <janet.h>
#include "fbink.h"

#include "otter_skia_hello.hh"

namespace {

void close_or_panic(int fbfd) {
    const int close_rv = fbink_close(fbfd);
    if (close_rv < 0) {
        const int saved = errno;
        janet_panicf("fbink_close failed: rv=%d errno=%d (%s)", close_rv, saved, std::strerror(saved));
    }
}

}  // namespace

static Janet cfun_self_test(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 0);
    (void) argv;

    SkBitmap bitmap;
    otter::RenderStats stats;
    if (!otter::render_hello_bitmap(640, 480, otter::kKoboHelloSkiaText, &bitmap, &stats)) {
        janet_panic("Skia render self-test allocation failed");
    }
    return janet_wrap_integer(stats.black_pixels);
}

static Janet cfun_render_hello(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 0);
    (void) argv;

    FBInkConfig cfg;
    std::memset(&cfg, 0, sizeof(cfg));
    cfg.is_quiet = true;
    cfg.is_flashing = true;
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

    SkBitmap bitmap;
    if (!otter::render_hello_bitmap(static_cast<int>(target_width), static_cast<int>(target_height), otter::kKoboHelloSkiaText, &bitmap, nullptr)) {
        fbink_close(fbfd);
        janet_panicf("Skia render allocation failed for framebuffer dimensions: %ux%u", target_width, target_height);
    }

    const void *pixels = bitmap.getPixels();
    const size_t byte_count = bitmap.computeByteSize();
    if (pixels == nullptr || byte_count == 0) {
        fbink_close(fbfd);
        janet_panic("Skia render produced an empty bitmap");
    }

    rv = fbink_print_raw_data(
        fbfd,
        static_cast<const unsigned char *>(pixels),
        static_cast<int>(target_width),
        static_cast<int>(target_height),
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
    return janet_wrap_integer(rv);
}

static const JanetReg cfuns[] = {
    {
        "self-test", cfun_self_test,
        "(skia/self-test)\n\n"
        "Render the Hello Skia demo off-screen and return the count of black pixels."
    },
    {
        "render-hello", cfun_render_hello,
        "(skia/render-hello)\n\n"
        "Render a white full-screen Skia bitmap with black centered `Hello Skia!` text and present it via FBInk."
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    janet_cfuns(env, "skia", cfuns);
}
