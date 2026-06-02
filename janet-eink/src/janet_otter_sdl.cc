#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <janet.h>
#include <SDL.h>

#include "otter_skia_hello.hh"

namespace {

struct Dimensions {
    int width = otter::kKoboScreenWidth;
    int height = otter::kKoboScreenHeight;
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
    if (dimensions.width <= 0 || dimensions.height <= 0) {
        janet_panicf("invalid SDL dimensions: %dx%d", dimensions.width, dimensions.height);
    }
    return dimensions;
}

Janet make_stats_table(const Dimensions &dimensions, const otter::RenderStats &stats) {
    JanetTable *table = janet_table(4);
    janet_table_put(table, janet_ckeywordv("width"), janet_wrap_integer(dimensions.width));
    janet_table_put(table, janet_ckeywordv("height"), janet_wrap_integer(dimensions.height));
    janet_table_put(table, janet_ckeywordv("text"), janet_cstringv(otter::kDesktopHelloSkiaText));
    janet_table_put(table, janet_ckeywordv("black-pixels"), janet_wrap_integer(stats.black_pixels));
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

bool present_bitmap(SDL_Renderer *renderer, SDL_Texture *texture, const SkBitmap &bitmap) {
    const void *pixels = bitmap.getPixels();
    if (pixels == nullptr) {
        return false;
    }
    if (SDL_UpdateTexture(texture, nullptr, pixels, static_cast<int>(bitmap.rowBytes())) != 0) {
        return false;
    }
    if (SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255) != 0) {
        return false;
    }
    if (SDL_RenderClear(renderer) != 0) {
        return false;
    }
    if (SDL_RenderCopy(renderer, texture, nullptr, nullptr) != 0) {
        return false;
    }
    SDL_RenderPresent(renderer);
    return true;
}

}  // namespace

static Janet cfun_render_self_test(int32_t argc, Janet *argv) {
    const Dimensions dimensions = get_dimensions(argc, argv);

    SkBitmap bitmap;
    otter::RenderStats stats;
    if (!otter::render_hello_bitmap(
            dimensions.width, dimensions.height, otter::kDesktopHelloSkiaText, &bitmap, &stats)) {
        janet_panicf("Skia render allocation failed for dimensions: %dx%d", dimensions.width, dimensions.height);
    }
    return make_stats_table(dimensions, stats);
}

static Janet cfun_run_hello(int32_t argc, Janet *argv) {
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

    if (SDL_RenderSetLogicalSize(renderer, dimensions.width, dimensions.height) != 0) {
        panic_sdl("SDL_RenderSetLogicalSize", texture, renderer, window, sdl_initialized);
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

    SkBitmap bitmap;
    if (!otter::render_hello_bitmap(
            dimensions.width, dimensions.height, otter::kDesktopHelloSkiaText, &bitmap, nullptr)) {
        panic_after_cleanup("Skia render allocation failed", texture, renderer, window, sdl_initialized);
    }

    if (!present_bitmap(renderer, texture, bitmap)) {
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
                    if (!present_bitmap(renderer, texture, bitmap)) {
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
        "render-self-test", cfun_render_self_test,
        "(desktop/render-self-test &opt width height)\n\n"
        "Render the Hello Skia demo off-screen and return render statistics."
    },
    {
        "run-hello", cfun_run_hello,
        "(desktop/run-hello &opt width height)\n\n"
        "Open an SDL window and present the Kobo-sized Hello Skia demo until the window is closed."
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    janet_cfuns(env, "desktop", cfuns);
}
