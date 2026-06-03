#ifndef OTTER_JANET_SKIA_COMMON_HH
#define OTTER_JANET_SKIA_COMMON_HH

#include <cstdint>

#include <janet.h>

#include "otter_drawing_backend.hh"

namespace otter::binding {

struct Dimensions {
    int width = otter::kKoboScreenWidth;
    int height = otter::kKoboScreenHeight;
};

Dimensions get_dimensions(int32_t argc, Janet *argv);
otter::GrayCanvas *get_canvas(Janet *argv, int32_t n);
otter::NormalizedPaint get_paint(Janet *argv, int32_t n);
Janet make_stats_table(const otter::GrayStats &stats);
Janet make_dimensions_table(int width, int height);
void register_common_cfuns(JanetTable *env, const char *prefix);

}  // namespace otter::binding

#endif  // OTTER_JANET_SKIA_COMMON_HH
