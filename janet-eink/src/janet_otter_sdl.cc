#include <climits>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <vector>

#include <janet.h>
#include <SDL.h>

#include "otter_drawing_backend.hh"

namespace {

struct Dimensions {
    int width = otter::kKoboScreenWidth;
    int height = otter::kKoboScreenHeight;
};

struct CanvasRect {
    int x = 0;
    int y = 0;
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

CanvasRect fixed_canvas_rect(int output_width, int output_height, const Dimensions &canvas) {
    CanvasRect rect;
    rect.x = (output_width - canvas.width) / 2;
    rect.y = (output_height - canvas.height) / 2;
    rect.width = canvas.width;
    rect.height = canvas.height;
    return rect;
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

Janet make_rect_table(const CanvasRect &rect) {
    JanetTable *table = janet_table(4);
    janet_table_put(table, janet_ckeywordv("x"), janet_wrap_integer(rect.x));
    janet_table_put(table, janet_ckeywordv("y"), janet_wrap_integer(rect.y));
    janet_table_put(table, janet_ckeywordv("width"), janet_wrap_integer(rect.width));
    janet_table_put(table, janet_ckeywordv("height"), janet_wrap_integer(rect.height));
    return janet_wrap_table(table);
}

void set_default_env(const char *name, const char *value) {
    if (std::getenv(name) == nullptr) {
        setenv(name, value, 0);
    }
}

void cleanup_sdl(SDL_Texture *texture, SDL_Renderer *renderer, SDL_Window *window, bool sdl_initialized) {
    if (texture != nullptr) {
        SDL_DestroyTexture(texture);
    }
    if (renderer != nullptr) {
        SDL_DestroyRenderer(renderer);
    }
    if (window != nullptr) {
        SDL_DestroyWindow(window);
    }
    if (sdl_initialized) {
        SDL_Quit();
    }
}

[[noreturn]] void panic_sdl(
    const char *operation,
    SDL_Texture *texture,
    SDL_Renderer *renderer,
    SDL_Window *window,
    bool sdl_initialized) {
    char error_message[512];
    const char *sdl_error = SDL_GetError();
    std::snprintf(
        error_message,
        sizeof(error_message),
        "%s failed: %s",
        operation,
        sdl_error != nullptr && sdl_error[0] != '\0' ? sdl_error : "unknown SDL error");
    cleanup_sdl(texture, renderer, window, sdl_initialized);
    janet_panicf("%s", error_message);
}

[[noreturn]] void panic_after_cleanup(
    const char *message,
    SDL_Texture *texture,
    SDL_Renderer *renderer,
    SDL_Window *window,
    bool sdl_initialized) {
    cleanup_sdl(texture, renderer, window, sdl_initialized);
    janet_panicf("%s", message);
}

bool present_canvas(
    SDL_Renderer *renderer, SDL_Texture *texture, const NativeCanvas &canvas, const Dimensions &canvas_dimensions) {
    std::vector<uint8_t> rgba;
    otter::gray8_to_rgba32(canvas, &rgba);

    if (SDL_UpdateTexture(texture, nullptr, rgba.data(), canvas_dimensions.width * 4) != 0) {
        return false;
    }

    int output_width = 0;
    int output_height = 0;
    if (SDL_GetRendererOutputSize(renderer, &output_width, &output_height) != 0) {
        return false;
    }
    const CanvasRect canvas_rect = fixed_canvas_rect(output_width, output_height, canvas_dimensions);
    const SDL_Rect destination = {canvas_rect.x, canvas_rect.y, canvas_rect.width, canvas_rect.height};

    if (SDL_SetRenderDrawColor(renderer, 64, 64, 64, 255) != 0) {
        return false;
    }
    if (SDL_RenderClear(renderer) != 0) {
        return false;
    }
    if (SDL_RenderCopy(renderer, texture, nullptr, &destination) != 0) {
        return false;
    }
    SDL_RenderPresent(renderer);
    return true;
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

static Janet cfun_render_demo_self_test(int32_t argc, Janet *argv) {
    const Dimensions dimensions = get_dimensions(argc, argv);
    NativeCanvas canvas;
    otter::GrayStats stats;
    if (!otter::render_demo_scene(dimensions.width, dimensions.height, &canvas, &stats)) {
        janet_panicf("Skia demo render allocation failed for dimensions: %dx%d", dimensions.width, dimensions.height);
    }
    return make_stats_table(stats);
}

static Janet cfun_fixed_viewport(int32_t argc, Janet *argv) {
    janet_arity(argc, 2, 4);
    const int output_width = janet_getinteger(argv, 0);
    const int output_height = janet_getinteger(argv, 1);
    if (output_width <= 0 || output_height <= 0) {
        janet_panicf("invalid SDL render output dimensions: %dx%d", output_width, output_height);
    }

    Dimensions canvas_dimensions;
    if (argc >= 3) {
        canvas_dimensions.width = janet_getinteger(argv, 2);
    }
    if (argc >= 4) {
        canvas_dimensions.height = janet_getinteger(argv, 3);
    }
    if (!otter::valid_dimensions(canvas_dimensions.width, canvas_dimensions.height)) {
        janet_panicf(
            "invalid fixed canvas dimensions: %dx%d", canvas_dimensions.width, canvas_dimensions.height);
    }

    return make_rect_table(fixed_canvas_rect(output_width, output_height, canvas_dimensions));
}

static Janet cfun_run_demo(int32_t argc, Janet *argv) {
    const Dimensions dimensions = get_dimensions(argc, argv);

    SDL_Texture *texture = nullptr;
    SDL_Renderer *renderer = nullptr;
    SDL_Window *window = nullptr;
    bool sdl_initialized = false;

    set_default_env("SDL_VIDEO_WAYLAND_WMCLASS", "Otter");
    set_default_env("SDL_VIDEO_X11_WMCLASS", "Otter");

    SDL_SetMainReady();
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
    SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
        panic_sdl("SDL_Init", texture, renderer, window, sdl_initialized);
    }
    sdl_initialized = true;
    SDL_EnableScreenSaver();

    const char *video_driver = SDL_GetCurrentVideoDriver();
    std::fprintf(stderr, "Otter SDL video driver: %s\n", video_driver != nullptr ? video_driver : "unknown");

    window = SDL_CreateWindow(
        "Otter",
        SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED,
        dimensions.width,
        dimensions.height,
        SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    if (window == nullptr) {
        panic_sdl("SDL_CreateWindow", texture, renderer, window, sdl_initialized);
    }

    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (renderer == nullptr) {
        SDL_ClearError();
        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
    }
    if (renderer == nullptr) {
        panic_sdl("SDL_CreateRenderer", texture, renderer, window, sdl_initialized);
    }

    texture = SDL_CreateTexture(
        renderer,
        SDL_PIXELFORMAT_RGBA32,
        SDL_TEXTUREACCESS_STREAMING,
        dimensions.width,
        dimensions.height);
    if (texture == nullptr) {
        panic_sdl("SDL_CreateTexture", texture, renderer, window, sdl_initialized);
    }

    NativeCanvas canvas;
    if (!otter::render_demo_scene(dimensions.width, dimensions.height, &canvas, nullptr)) {
        panic_after_cleanup("Skia demo render allocation failed", texture, renderer, window, sdl_initialized);
    }

    if (!present_canvas(renderer, texture, canvas, dimensions)) {
        panic_sdl("SDL present", texture, renderer, window, sdl_initialized);
    }

    bool running = true;
    while (running) {
        SDL_Event event;
        if (SDL_WaitEvent(&event) == 0) {
            panic_sdl("SDL_WaitEvent", texture, renderer, window, sdl_initialized);
        }

        switch (event.type) {
            case SDL_QUIT:
                running = false;
                break;
            case SDL_KEYDOWN:
                if (event.key.keysym.sym == SDLK_ESCAPE || event.key.keysym.sym == SDLK_q) {
                    running = false;
                }
                break;
            case SDL_WINDOWEVENT:
                if (event.window.event == SDL_WINDOWEVENT_EXPOSED ||
                    event.window.event == SDL_WINDOWEVENT_RESIZED ||
                    event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
                    if (!present_canvas(renderer, texture, canvas, dimensions)) {
                        panic_sdl("SDL present", texture, renderer, window, sdl_initialized);
                    }
                }
                break;
            default:
                break;
        }
    }

    cleanup_sdl(texture, renderer, window, sdl_initialized);
    return janet_wrap_integer(0);
}

static const JanetReg cfuns[] = {
    {
        "create", cfun_create,
        "(desktop/create &opt width height)\n\n"
        "Create a gray8 Skia canvas."
    },
    {
        "clear", cfun_clear,
        "(desktop/clear canvas gray)\n\n"
        "Fill a gray8 canvas with a gray value in 0..255."
    },
    {
        "draw-rect", cfun_draw_rect,
        "(desktop/draw-rect canvas x y width height gray)\n\n"
        "Draw a filled rectangle on a gray8 canvas."
    },
    {
        "draw-round-rect", cfun_draw_round_rect,
        "(desktop/draw-round-rect canvas x y width height radius gray)\n\n"
        "Draw a filled rounded rectangle on a gray8 canvas."
    },
    {
        "draw-triangle", cfun_draw_triangle,
        "(desktop/draw-triangle canvas x1 y1 x2 y2 x3 y3 gray)\n\n"
        "Draw a filled triangle on a gray8 canvas."
    },
    {
        "draw-circle", cfun_draw_circle,
        "(desktop/draw-circle canvas cx cy radius gray)\n\n"
        "Draw a filled circle on a gray8 canvas."
    },
    {
        "sample-gray", cfun_sample_gray,
        "(desktop/sample-gray canvas x y)\n\n"
        "Return the gray value at a canvas pixel."
    },
    {
        "stats", cfun_stats,
        "(desktop/stats canvas)\n\n"
        "Return gray8 canvas statistics."
    },
    {
        "render-demo-self-test", cfun_render_demo_self_test,
        "(desktop/render-demo-self-test &opt width height)\n\n"
        "Render the gray shape demo off-screen and return render statistics."
    },
    {
        "fixed-viewport", cfun_fixed_viewport,
        "(desktop/fixed-viewport output-width output-height &opt canvas-width canvas-height)\n\n"
        "Return the fixed Kobo canvas rectangle centered in an SDL render output."
    },
    {
        "run-demo", cfun_run_demo,
        "(desktop/run-demo &opt width height)\n\n"
        "Open an SDL window and present the Kobo-sized gray shape demo until the window is closed."
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    janet_cfuns(env, "desktop", cfuns);
}
