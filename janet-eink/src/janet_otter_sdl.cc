#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include <janet.h>
#include <SDL.h>
#include "core/SkCanvas.h"
#include "core/SkColor.h"
#include "core/SkFont.h"
#include "core/SkImageInfo.h"
#include "core/SkPaint.h"
#include "core/SkPixmap.h"
#include "core/SkRect.h"
#include "core/SkSurface.h"

#include "janet_skia_common.hh"
#include "otter_drawing_backend.hh"

namespace {

struct Rgba {
    std::uint8_t r = 0;
    std::uint8_t g = 0;
    std::uint8_t b = 0;
    std::uint8_t a = 255;
};

struct ButtonStyle {
    Rgba background;
    Rgba border;
    Rgba label;
};

struct ButtonInteraction {
    bool hovered = false;
    bool pressed = false;
};

constexpr int kChromeButtonWidth = 112;
constexpr int kChromeButtonHeight = 30;
constexpr int kChromeButtonGap = 12;
constexpr int kChromeInitialPaddingX = 24;
constexpr int kChromeInitialPaddingY = 12;
constexpr float kChromeButtonLabelFontSize = 14.0f;
constexpr const char *kChromeButtonLabel = "Press Me";
constexpr Rgba kButtonBackground = {224, 224, 224, 255};
constexpr Rgba kButtonPressedBackground = {176, 176, 176, 255};
constexpr Rgba kButtonBorder = {16, 16, 16, 255};
constexpr Rgba kButtonHoverBorder = {64, 128, 224, 255};
constexpr Rgba kButtonLabel = {16, 16, 16, 255};

struct CanvasRect {
    int x = 0;
    int y = 0;
    int width = otter::kKoboScreenWidth;
    int height = otter::kKoboScreenHeight;
};

struct ChromeLayout {
    CanvasRect canvas;
    CanvasRect button;
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

ChromeLayout chrome_layout(int output_width, int output_height, int canvas_width, int canvas_height) {
    const int display_width = display_dimension(canvas_width);
    const int display_height = display_dimension(canvas_height);
    const int content_height = display_height + kChromeButtonGap + kChromeButtonHeight;

    ChromeLayout layout;
    layout.canvas.x = (output_width - display_width) / 2;
    layout.canvas.y = (output_height - content_height) / 2;
    layout.canvas.width = display_width;
    layout.canvas.height = display_height;

    layout.button.x = (output_width - kChromeButtonWidth) / 2;
    layout.button.y = layout.canvas.y + display_height + kChromeButtonGap;
    layout.button.width = kChromeButtonWidth;
    layout.button.height = kChromeButtonHeight;
    return layout;
}

int chrome_window_width(int canvas_width) {
    return display_dimension(canvas_width) + (kChromeInitialPaddingX * 2);
}

int chrome_window_height(int canvas_height) {
    return display_dimension(canvas_height) + kChromeButtonGap + kChromeButtonHeight + (kChromeInitialPaddingY * 2);
}

bool rect_contains(const CanvasRect &rect, int x, int y) {
    return x >= rect.x &&
           y >= rect.y &&
           x < rect.x + rect.width &&
           y < rect.y + rect.height;
}

bool chrome_button_hit(int output_width, int output_height, int canvas_width, int canvas_height, int x, int y) {
    return rect_contains(chrome_layout(output_width, output_height, canvas_width, canvas_height).button, x, y);
}

ButtonStyle button_style(bool hovered, bool pressed) {
    ButtonStyle style;
    style.background = pressed ? kButtonPressedBackground : kButtonBackground;
    style.border = hovered ? kButtonHoverBorder : kButtonBorder;
    style.label = kButtonLabel;
    return style;
}

ButtonStyle button_style(const ButtonInteraction &interaction) {
    return button_style(interaction.hovered, interaction.pressed);
}

bool update_button_interaction(ButtonInteraction *interaction, bool hovered, bool pressed) {
    const bool changed = interaction->hovered != hovered || interaction->pressed != pressed;
    interaction->hovered = hovered;
    interaction->pressed = pressed;
    return changed;
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

bool set_renderer_color(SDL_Renderer *renderer, const Rgba &color) {
    return SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a) == 0;
}

SkColor sk_color(const Rgba &color) {
    return SkColorSetARGB(color.a, color.r, color.g, color.b);
}

bool draw_shaped_button_label(SkCanvas *canvas, otter::GrayCanvas &font_source, int width, int height, const Rgba &color) {
    otter::FontOptions font_options;
    font_options.family = "Noto Sans";
    font_options.size = kChromeButtonLabelFontSize;

    otter::TextLine line;
    std::string error_message;
    if (!otter::shape_text(font_source, kChromeButtonLabel, font_options, "", &line, &error_message) || !line.blob) {
        return false;
    }

    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setColor(sk_color(color));

    const float x = std::max(0.0f, (static_cast<float>(width) - line.metrics.width) / 2.0f);
    const float y = std::max(0.0f, (static_cast<float>(height) - line.metrics.height) / 2.0f);
    canvas->drawTextBlob(line.blob, x, y + line.metrics.height, paint);
    return true;
}

void draw_simple_button_label(SkCanvas *canvas, int width, int height, const Rgba &color) {
    SkFont font(nullptr, kChromeButtonLabelFontSize);
    font.setEdging(SkFont::Edging::kAntiAlias);

    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setColor(sk_color(color));

    SkRect bounds;
    const std::size_t label_size = std::strlen(kChromeButtonLabel);
    font.measureText(kChromeButtonLabel, label_size, SkTextEncoding::kUTF8, &bounds);
    const float x = ((static_cast<float>(width) - bounds.width()) / 2.0f) - bounds.left();
    const float y = ((static_cast<float>(height) - bounds.height()) / 2.0f) - bounds.top();
    canvas->drawSimpleText(kChromeButtonLabel, label_size, SkTextEncoding::kUTF8, x, y, font, paint);
}

bool render_button_label(SDL_Renderer *renderer, otter::GrayCanvas &font_source, const CanvasRect &button, const Rgba &color) {
    const SkImageInfo info = SkImageInfo::Make(
        button.width,
        button.height,
        kRGBA_8888_SkColorType,
        kPremul_SkAlphaType);
    sk_sp<SkSurface> surface = SkSurfaces::Raster(info);
    if (!surface) {
        return false;
    }

    SkCanvas *label_canvas = surface->getCanvas();
    label_canvas->clear(SK_ColorTRANSPARENT);
    if (!draw_shaped_button_label(label_canvas, font_source, button.width, button.height, color)) {
        draw_simple_button_label(label_canvas, button.width, button.height, color);
    }

    SkPixmap pixmap;
    if (!surface->peekPixels(&pixmap)) {
        return false;
    }

    SDL_Texture *texture = SDL_CreateTexture(
        renderer,
        SDL_PIXELFORMAT_RGBA32,
        SDL_TEXTUREACCESS_STATIC,
        button.width,
        button.height);
    if (texture == nullptr) {
        return false;
    }

    bool ok = true;
    if (SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND) != 0) {
        ok = false;
    }
    if (ok && SDL_UpdateTexture(texture, nullptr, pixmap.addr(), static_cast<int>(pixmap.rowBytes())) != 0) {
        ok = false;
    }
    const SDL_Rect destination = {button.x, button.y, button.width, button.height};
    if (ok && SDL_RenderCopy(renderer, texture, nullptr, &destination) != 0) {
        ok = false;
    }
    SDL_DestroyTexture(texture);
    return ok;
}

bool render_button(SDL_Renderer *renderer, otter::GrayCanvas &font_source, const CanvasRect &button, const ButtonStyle &style) {
    const SDL_Rect rect = {button.x, button.y, button.width, button.height};
    if (!set_renderer_color(renderer, style.background)) {
        return false;
    }
    if (SDL_RenderFillRect(renderer, &rect) != 0) {
        return false;
    }
    if (!set_renderer_color(renderer, style.border)) {
        return false;
    }
    if (SDL_RenderDrawRect(renderer, &rect) != 0) {
        return false;
    }

    return render_button_label(renderer, font_source, button, style.label);
}

bool render_chrome(SDL_Renderer *renderer, otter::GrayCanvas &canvas, const ChromeLayout &layout, const ButtonInteraction &button_interaction) {
    const SDL_Rect frame = {layout.canvas.x - 2, layout.canvas.y - 2, layout.canvas.width + 4, layout.canvas.height + 4};
    if (SDL_SetRenderDrawColor(renderer, 24, 24, 24, 255) != 0) {
        return false;
    }
    if (SDL_RenderDrawRect(renderer, &frame) != 0) {
        return false;
    }
    return render_button(renderer, canvas, layout.button, button_style(button_interaction));
}

void map_window_point_to_output(
    SDL_Window *window,
    int output_width,
    int output_height,
    int window_x,
    int window_y,
    int *output_x,
    int *output_y) {
    int window_width = 0;
    int window_height = 0;
    SDL_GetWindowSize(window, &window_width, &window_height);
    if (window_width <= 0 || window_height <= 0) {
        *output_x = window_x;
        *output_y = window_y;
        return;
    }
    *output_x = static_cast<int>((static_cast<long long>(window_x) * output_width) / window_width);
    *output_y = static_cast<int>((static_cast<long long>(window_y) * output_height) / window_height);
}

bool button_hit_for_window_point(
    SDL_Renderer *renderer,
    SDL_Window *window,
    const otter::GrayCanvas &canvas,
    int window_x,
    int window_y,
    bool *hit) {
    int output_width = 0;
    int output_height = 0;
    if (SDL_GetRendererOutputSize(renderer, &output_width, &output_height) != 0) {
        return false;
    }
    int output_x = 0;
    int output_y = 0;
    map_window_point_to_output(
        window,
        output_width,
        output_height,
        window_x,
        window_y,
        &output_x,
        &output_y);
    *hit = chrome_button_hit(output_width, output_height, canvas.width(), canvas.height(), output_x, output_y);
    return true;
}

bool present_canvas(
    SDL_Renderer *renderer,
    SDL_Texture *texture,
    otter::GrayCanvas &canvas,
    const ButtonInteraction &button_interaction) {
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
    const ChromeLayout layout = chrome_layout(output_width, output_height, canvas.width(), canvas.height());
    const SDL_Rect destination = {layout.canvas.x, layout.canvas.y, layout.canvas.width, layout.canvas.height};

    if (SDL_SetRenderDrawColor(renderer, 64, 64, 64, 255) != 0) {
        return false;
    }
    if (SDL_RenderClear(renderer) != 0) {
        return false;
    }
    if (SDL_RenderCopy(renderer, texture, nullptr, &destination) != 0) {
        return false;
    }
    if (!render_chrome(renderer, canvas, layout, button_interaction)) {
        return false;
    }
    SDL_RenderPresent(renderer);
    return true;
}

void redraw_canvas(
    SDL_Texture *texture,
    SDL_Renderer *renderer,
    SDL_Window *window,
    bool sdl_initialized,
    otter::GrayCanvas &canvas,
    const ButtonInteraction &button_interaction) {
    if (!present_canvas(renderer, texture, canvas, button_interaction)) {
        panic_sdl("SDL present", texture, renderer, window, sdl_initialized);
    }
}

void run_event_loop(
    SDL_Texture *texture,
    SDL_Renderer *renderer,
    SDL_Window *window,
    bool sdl_initialized,
    otter::GrayCanvas &canvas,
    ButtonInteraction button_interaction) {
    bool running = true;
    bool press_started_on_button = false;

    auto redraw_if_changed = [&](bool hovered, bool pressed) {
        if (update_button_interaction(&button_interaction, hovered, pressed)) {
            redraw_canvas(texture, renderer, window, sdl_initialized, canvas, button_interaction);
        }
    };

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
            case SDL_MOUSEMOTION: {
                bool hit = false;
                if (!button_hit_for_window_point(renderer, window, canvas, event.motion.x, event.motion.y, &hit)) {
                    panic_sdl("SDL_GetRendererOutputSize", texture, renderer, window, sdl_initialized);
                }
                const bool left_down = (event.motion.state & SDL_BUTTON_LMASK) != 0;
                if (!left_down) {
                    press_started_on_button = false;
                }
                redraw_if_changed(hit, press_started_on_button && left_down && hit);
                break;
            }
            case SDL_MOUSEBUTTONDOWN:
                if (event.button.button == SDL_BUTTON_LEFT) {
                    bool hit = false;
                    if (!button_hit_for_window_point(renderer, window, canvas, event.button.x, event.button.y, &hit)) {
                        panic_sdl("SDL_GetRendererOutputSize", texture, renderer, window, sdl_initialized);
                    }
                    press_started_on_button = hit;
                    redraw_if_changed(hit, hit);
                }
                break;
            case SDL_MOUSEBUTTONUP:
                if (event.button.button == SDL_BUTTON_LEFT) {
                    bool hit = false;
                    if (!button_hit_for_window_point(renderer, window, canvas, event.button.x, event.button.y, &hit)) {
                        panic_sdl("SDL_GetRendererOutputSize", texture, renderer, window, sdl_initialized);
                    }
                    const bool clicked = press_started_on_button && hit;
                    press_started_on_button = false;
                    redraw_if_changed(hit, false);
                    if (clicked) {
                        std::printf("hello world\n");
                        std::fflush(stdout);
                    }
                }
                break;
            case SDL_WINDOWEVENT:
                if (event.window.event == SDL_WINDOWEVENT_LEAVE) {
                    press_started_on_button = false;
                    redraw_if_changed(false, false);
                } else if (event.window.event == SDL_WINDOWEVENT_EXPOSED ||
                           event.window.event == SDL_WINDOWEVENT_RESIZED ||
                           event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
                    redraw_canvas(texture, renderer, window, sdl_initialized, canvas, button_interaction);
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
        chrome_window_width(canvas->width()),
        chrome_window_height(canvas->height()),
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

    ButtonInteraction button_interaction;
    if (!present_canvas(renderer, texture, *canvas, button_interaction)) {
        panic_sdl("SDL present", texture, renderer, window, sdl_initialized);
    }

    if (block) {
        run_event_loop(texture, renderer, window, sdl_initialized, *canvas, button_interaction);
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
        "Open an SDL window, present a gray8 canvas with desktop diagnostics chrome, and optionally run the static event loop."
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    otter::binding::register_common_cfuns(env, "skia");
    janet_cfuns(env, "skia", platform_cfuns);
}
