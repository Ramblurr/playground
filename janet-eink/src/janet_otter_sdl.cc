#include <cstdio>
#include <cstdlib>
#include <vector>

#include <janet.h>
#include <SDL.h>

#include "janet_skia_common.hh"
#include "otter_drawing_backend.hh"

namespace {

struct CanvasRect {
    int x = 0;
    int y = 0;
    int width = otter::kKoboScreenWidth;
    int height = otter::kKoboScreenHeight;
};

int display_dimension(int canvas_dimension) {
    const int scaled = canvas_dimension / 2;
    return scaled > 0 ? scaled : 1;
}

CanvasRect fixed_canvas_rect(int output_width, int output_height, int canvas_width, int canvas_height) {
    const int display_width = display_dimension(canvas_width);
    const int display_height = display_dimension(canvas_height);
    CanvasRect rect;
    rect.x = (output_width - display_width) / 2;
    rect.y = (output_height - display_height) / 2;
    rect.width = display_width;
    rect.height = display_height;
    return rect;
}

Janet make_rect_table(const CanvasRect &rect) {
    JanetTable *table = janet_table(4);
    janet_table_put(table, janet_ckeywordv("x"), janet_wrap_integer(rect.x));
    janet_table_put(table, janet_ckeywordv("y"), janet_wrap_integer(rect.y));
    janet_table_put(table, janet_ckeywordv("width"), janet_wrap_integer(rect.width));
    janet_table_put(table, janet_ckeywordv("height"), janet_wrap_integer(rect.height));
    return janet_wrap_table(table);
}

bool dictionary_like(Janet value) {
    return janet_checktype(value, JANET_TABLE) || janet_checktype(value, JANET_STRUCT);
}

bool option_bool(Janet options, const char *key, bool default_value) {
    if (!dictionary_like(options)) {
        return default_value;
    }
    Janet value = janet_get(options, janet_ckeywordv(key));
    if (janet_checktype(value, JANET_NIL)) {
        return default_value;
    }
    return janet_truthy(value);
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

bool present_canvas(
    SDL_Renderer *renderer,
    SDL_Texture *texture,
    const otter::GrayCanvas &canvas) {
    std::vector<std::uint8_t> rgba;
    otter::gray8_to_rgba32(canvas, &rgba);

    if (SDL_UpdateTexture(texture, nullptr, rgba.data(), canvas.width() * 4) != 0) {
        return false;
    }

    int output_width = 0;
    int output_height = 0;
    if (SDL_GetRendererOutputSize(renderer, &output_width, &output_height) != 0) {
        return false;
    }
    const CanvasRect canvas_rect = fixed_canvas_rect(output_width, output_height, canvas.width(), canvas.height());
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

void run_event_loop(
    SDL_Texture *texture,
    SDL_Renderer *renderer,
    SDL_Window *window,
    bool sdl_initialized,
    const otter::GrayCanvas &canvas) {
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
                    if (!present_canvas(renderer, texture, canvas)) {
                        panic_sdl("SDL present", texture, renderer, window, sdl_initialized);
                    }
                }
                break;
            default:
                break;
        }
    }
}

}  // namespace

static Janet cfun_fixed_viewport(int32_t argc, Janet *argv) {
    janet_arity(argc, 2, 4);
    const int output_width = janet_getinteger(argv, 0);
    const int output_height = janet_getinteger(argv, 1);
    if (output_width <= 0 || output_height <= 0) {
        janet_panicf("invalid SDL render output dimensions: %dx%d", output_width, output_height);
    }

    int canvas_width = otter::kKoboScreenWidth;
    int canvas_height = otter::kKoboScreenHeight;
    if (argc >= 3) {
        canvas_width = janet_getinteger(argv, 2);
    }
    if (argc >= 4) {
        canvas_height = janet_getinteger(argv, 3);
    }
    if (!otter::valid_dimensions(canvas_width, canvas_height)) {
        janet_panicf("invalid fixed canvas dimensions: %dx%d", canvas_width, canvas_height);
    }

    return make_rect_table(fixed_canvas_rect(output_width, output_height, canvas_width, canvas_height));
}

static Janet cfun_present(int32_t argc, Janet *argv) {
    janet_arity(argc, 1, 2);
    otter::GrayCanvas *canvas = otter::binding::get_canvas(argv, 0);
    Janet options = argc >= 2 ? argv[1] : janet_wrap_nil();
    const bool block = option_bool(options, "block?", true);

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
        display_dimension(canvas->width()),
        display_dimension(canvas->height()),
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
        canvas->width(),
        canvas->height());
    if (texture == nullptr) {
        panic_sdl("SDL_CreateTexture", texture, renderer, window, sdl_initialized);
    }

    if (!present_canvas(renderer, texture, *canvas)) {
        panic_sdl("SDL present", texture, renderer, window, sdl_initialized);
    }

    if (block) {
        run_event_loop(texture, renderer, window, sdl_initialized, *canvas);
    }

    cleanup_sdl(texture, renderer, window, sdl_initialized);
    return janet_wrap_integer(0);
}

static const JanetReg platform_cfuns[] = {
    {
        "fixed-viewport", cfun_fixed_viewport,
        "(skia/fixed-viewport output-width output-height &opt canvas-width canvas-height)\n\n"
        "Return the fixed Kobo canvas rectangle centered in an SDL render output."
    },
    {
        "present", cfun_present,
        "(skia/present canvas &opt options)\n\n"
        "Open an SDL window, present a gray8 canvas, and optionally run the static event loop."
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    otter::binding::register_common_cfuns(env, "skia");
    janet_cfuns(env, "skia", platform_cfuns);
}
