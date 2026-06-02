#ifndef OTTER_SKIA_HELLO_HH
#define OTTER_SKIA_HELLO_HH

#include "core/SkBitmap.h"

namespace otter {

constexpr int kKoboScreenWidth = 1680;
constexpr int kKoboScreenHeight = 1264;
constexpr const char *kDesktopHelloSkiaText = "HELLO SKIA";
constexpr const char *kKoboHelloSkiaText = "Hello Skia!";

struct RenderStats {
    int black_pixels = 0;
};

bool render_hello_bitmap(int width, int height, const char *text, SkBitmap *bitmap, RenderStats *stats);

}  // namespace otter

#endif  // OTTER_SKIA_HELLO_HH
