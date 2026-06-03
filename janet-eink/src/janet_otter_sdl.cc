#include <algorithm>
#include <cstddef>
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
#include "core/SkPath.h"
#include "core/SkPathBuilder.h"
#include "core/SkRect.h"
#include "core/SkRRect.h"
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
constexpr const char *kBezelEnv = "OTTER_SDL_BEZEL";
constexpr Rgba kButtonBackground = {224, 224, 224, 255};
constexpr Rgba kButtonPressedBackground = {176, 176, 176, 255};
constexpr Rgba kButtonBorder = {16, 16, 16, 255};
constexpr Rgba kButtonHoverBorder = {64, 128, 224, 255};
constexpr Rgba kButtonLabel = {16, 16, 16, 255};

enum class HardwareControlKind {
    PageTurnButton,
};

struct ReferenceMargins {
    float left = 0.0f;
    float right = 0.0f;
    float top = 0.0f;
    float bottom = 0.0f;
};

struct ReferenceRect {
    float x = 0.0f;
    float y = 0.0f;
    float width = 0.0f;
    float height = 0.0f;
};

struct DeviceBodySpec {
    ReferenceMargins screen_margins;
    float outer_left_radius = 0.0f;
    float outer_right_radius = 0.0f;
    float screen_corner_radius = 0.0f;
    float stroke_width = 1.0f;
    Rgba fill = {230, 230, 230, 255};
    Rgba stroke = {0, 0, 0, 255};
};

struct HardwareControlSpec {
    const char *id = nullptr;
    HardwareControlKind kind = HardwareControlKind::PageTurnButton;
    ReferenceRect rect;
    float corner_radius = 0.0f;
    Rgba fill = {255, 255, 255, 255};
    Rgba stroke = {0, 0, 0, 255};
};

struct BezelSpec {
    const char *id = nullptr;
    const char *label = nullptr;
    float reference_screen_width = 1.0f;
    float reference_screen_height = 1.0f;
    DeviceBodySpec body;
    const HardwareControlSpec *hardware_controls = nullptr;
    std::size_t hardware_control_count = 0;
};

constexpr float kLibraReferenceScreenWidth = 10723.90f;
constexpr float kLibraReferenceScreenHeight = 14197.46f;
constexpr float kLibraPageButtonWidth = 405.49f;
constexpr float kLibraPageButtonHeight = 1937.02f;

constexpr HardwareControlSpec kKoboLibraH2OControls[] = {
    {
        "page-back",
        HardwareControlKind::PageTurnButton,
        {12213.11f, 4434.47f, kLibraPageButtonWidth, kLibraPageButtonHeight},
        kLibraPageButtonWidth / 2.0f,
        {255, 255, 255, 255},
        {0, 0, 0, 255},
    },
    {
        "page-forward",
        HardwareControlKind::PageTurnButton,
        {12213.11f, 7851.35f, kLibraPageButtonWidth, kLibraPageButtonHeight},
        kLibraPageButtonWidth / 2.0f,
        {255, 255, 255, 255},
        {0, 0, 0, 255},
    },
};

constexpr BezelSpec kKoboLibraH2OBezel = {
    "kobo-libra-h2o",
    "Kobo Libra H2O",
    kLibraReferenceScreenWidth,
    kLibraReferenceScreenHeight,
    {
        {717.45f, 2678.69f, 747.51f, 747.50f},
        299.95f,
        999.82f,
        124.98f,
        20.0f,
        {230, 230, 230, 255},
        {0, 0, 0, 255},
    },
    kKoboLibraH2OControls,
    sizeof(kKoboLibraH2OControls) / sizeof(kKoboLibraH2OControls[0]),
};

struct CanvasRect {
    int x = 0;
    int y = 0;
    int width = otter::kKoboScreenWidth;
    int height = otter::kKoboScreenHeight;
};

struct ChromeLayout {
    const BezelSpec *bezel = nullptr;
    CanvasRect device;
    CanvasRect canvas;
    CanvasRect button;
};

int display_dimension(int canvas_dimension) {
    const int scaled = canvas_dimension / 2;
    return scaled > 0 ? scaled : 1;
}

float scale_reference_xf(const BezelSpec &bezel, float units, int screen_width) {
    return units * static_cast<float>(screen_width) / bezel.reference_screen_width;
}

float scale_reference_yf(const BezelSpec &bezel, float units, int screen_height) {
    return units * static_cast<float>(screen_height) / bezel.reference_screen_height;
}

int scale_reference_x(const BezelSpec &bezel, float units, int screen_width) {
    return static_cast<int>(scale_reference_xf(bezel, units, screen_width) + 0.5f);
}

int scale_reference_y(const BezelSpec &bezel, float units, int screen_height) {
    return static_cast<int>(scale_reference_yf(bezel, units, screen_height) + 0.5f);
}

int device_width_for_screen(const BezelSpec *bezel, int screen_width) {
    if (bezel == nullptr) {
        return screen_width;
    }
    const ReferenceMargins &margins = bezel->body.screen_margins;
    return screen_width + scale_reference_x(*bezel, margins.left, screen_width) + scale_reference_x(*bezel, margins.right, screen_width);
}

int device_height_for_screen(const BezelSpec *bezel, int screen_height) {
    if (bezel == nullptr) {
        return screen_height;
    }
    const ReferenceMargins &margins = bezel->body.screen_margins;
    return screen_height + scale_reference_y(*bezel, margins.top, screen_height) + scale_reference_y(*bezel, margins.bottom, screen_height);
}

const BezelSpec *bezel_spec_for_id(const char *id) {
    if (id == nullptr || id[0] == '\0' || std::strcmp(id, kKoboLibraH2OBezel.id) == 0) {
        return &kKoboLibraH2OBezel;
    }
    if (std::strcmp(id, "none") == 0) {
        return nullptr;
    }
    std::fprintf(stderr, "Unknown %s=%s; falling back to %s\n", kBezelEnv, id, kKoboLibraH2OBezel.id);
    return &kKoboLibraH2OBezel;
}

const BezelSpec *selected_bezel_spec() {
    return bezel_spec_for_id(std::getenv(kBezelEnv));
}

const char *bezel_id(const BezelSpec *bezel) {
    return bezel != nullptr ? bezel->id : "none";
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

ChromeLayout chrome_layout(const BezelSpec *bezel, int output_width, int output_height, int canvas_width, int canvas_height) {
    const int display_width = display_dimension(canvas_width);
    const int display_height = display_dimension(canvas_height);
    const int device_width = device_width_for_screen(bezel, display_width);
    const int device_height = device_height_for_screen(bezel, display_height);
    const int content_width = std::max(device_width, kChromeButtonWidth);
    const int content_height = device_height + kChromeButtonGap + kChromeButtonHeight;

    ChromeLayout layout;
    layout.bezel = bezel;
    layout.device.x = (output_width - content_width) / 2 + ((content_width - device_width) / 2);
    layout.device.y = (output_height - content_height) / 2;
    layout.device.width = device_width;
    layout.device.height = device_height;

    layout.canvas.width = display_width;
    layout.canvas.height = display_height;
    if (bezel != nullptr) {
        const ReferenceMargins &margins = bezel->body.screen_margins;
        layout.canvas.x = layout.device.x + scale_reference_x(*bezel, margins.left, display_width);
        layout.canvas.y = layout.device.y + scale_reference_y(*bezel, margins.top, display_height);
    } else {
        layout.canvas.x = layout.device.x;
        layout.canvas.y = layout.device.y;
    }

    layout.button.x = (output_width - kChromeButtonWidth) / 2;
    layout.button.y = layout.device.y + device_height + kChromeButtonGap;
    layout.button.width = kChromeButtonWidth;
    layout.button.height = kChromeButtonHeight;
    return layout;
}

int chrome_window_width(const BezelSpec *bezel, int canvas_width) {
    const int display_width = display_dimension(canvas_width);
    return std::max(device_width_for_screen(bezel, display_width), kChromeButtonWidth) + (kChromeInitialPaddingX * 2);
}

int chrome_window_height(const BezelSpec *bezel, int canvas_height) {
    const int display_height = display_dimension(canvas_height);
    return device_height_for_screen(bezel, display_height) + kChromeButtonGap + kChromeButtonHeight + (kChromeInitialPaddingY * 2);
}

bool rect_contains(const CanvasRect &rect, int x, int y) {
    return x >= rect.x &&
           y >= rect.y &&
           x < rect.x + rect.width &&
           y < rect.y + rect.height;
}

bool chrome_button_hit(const BezelSpec *bezel, int output_width, int output_height, int canvas_width, int canvas_height, int x, int y) {
    return rect_contains(chrome_layout(bezel, output_width, output_height, canvas_width, canvas_height).button, x, y);
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

SkColor sk_color(const Rgba &color) {
    return SkColorSetARGB(color.a, color.r, color.g, color.b);
}

SkRect sk_rect(const CanvasRect &rect) {
    return SkRect::MakeXYWH(
        static_cast<float>(rect.x),
        static_cast<float>(rect.y),
        static_cast<float>(rect.width),
        static_cast<float>(rect.height));
}

float clamped_radius(float radius, const CanvasRect &rect) {
    return std::min(radius, static_cast<float>(std::min(rect.width, rect.height)) / 2.0f);
}

SkPaint fill_paint(const Rgba &color) {
    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setStyle(SkPaint::kFill_Style);
    paint.setColor(sk_color(color));
    return paint;
}

SkPaint stroke_paint(const Rgba &color, float stroke_width) {
    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setStyle(SkPaint::kStroke_Style);
    paint.setStrokeWidth(stroke_width);
    paint.setColor(sk_color(color));
    return paint;
}

void add_device_outline(SkPathBuilder *builder, const CanvasRect &device, float left_radius, float right_radius) {
    const float x = static_cast<float>(device.x);
    const float y = static_cast<float>(device.y);
    const float w = static_cast<float>(device.width);
    const float h = static_cast<float>(device.height);
    const float left = clamped_radius(left_radius, device);
    const float right = clamped_radius(right_radius, device);

    const SkRect rect = SkRect::MakeXYWH(x, y, w, h);
    const SkVector radii[4] = {
        {left, left},
        {right, right},
        {right, right},
        {left, left},
    };
    SkRRect outline;
    outline.setRectRadii(rect, radii);
    builder->addRRect(outline, SkPathDirection::kCW);
}

CanvasRect hardware_control_rect(const BezelSpec &bezel, const CanvasRect &screen, const HardwareControlSpec &control) {
    CanvasRect rect;
    rect.x = screen.x + scale_reference_x(bezel, control.rect.x, screen.width);
    rect.y = screen.y + scale_reference_y(bezel, control.rect.y, screen.height);
    rect.width = std::max(1, scale_reference_x(bezel, control.rect.width, screen.width));
    rect.height = std::max(1, scale_reference_y(bezel, control.rect.height, screen.height));
    return rect;
}

void draw_hardware_control(SkCanvas *canvas, const BezelSpec &bezel, const CanvasRect &screen, const HardwareControlSpec &control) {
    switch (control.kind) {
        case HardwareControlKind::PageTurnButton: {
            const CanvasRect bounds = hardware_control_rect(bezel, screen, control);
            const SkRect rect = sk_rect(bounds);
            const float radius = clamped_radius(scale_reference_xf(bezel, control.corner_radius, screen.width), bounds);
            canvas->drawRoundRect(rect, radius, radius, fill_paint(control.fill));
            canvas->drawRoundRect(rect, radius, radius, stroke_paint(control.stroke, std::max(1.0f, scale_reference_xf(bezel, bezel.body.stroke_width, screen.width))));
            break;
        }
    }
}

void draw_hardware_controls(SkCanvas *canvas, const BezelSpec &bezel, const CanvasRect &screen) {
    for (std::size_t i = 0; i < bezel.hardware_control_count; ++i) {
        draw_hardware_control(canvas, bezel, screen, bezel.hardware_controls[i]);
    }
}

void draw_device_bezel(SkCanvas *canvas, const ChromeLayout &layout) {
    const BezelSpec *bezel = layout.bezel;
    if (bezel == nullptr) {
        return;
    }

    SkPathBuilder builder;
    builder.setFillType(SkPathFillType::kEvenOdd);
    add_device_outline(
        &builder,
        layout.device,
        scale_reference_xf(*bezel, bezel->body.outer_left_radius, layout.canvas.width),
        scale_reference_xf(*bezel, bezel->body.outer_right_radius, layout.canvas.width));
    const float screen_radius = scale_reference_xf(*bezel, bezel->body.screen_corner_radius, layout.canvas.width);
    SkRRect screen;
    screen.setRectXY(sk_rect(layout.canvas), screen_radius, screen_radius);
    builder.addRRect(screen, SkPathDirection::kCW);
    const SkPath body = builder.detach();

    const float stroke_width = std::max(1.0f, scale_reference_xf(*bezel, bezel->body.stroke_width, layout.canvas.width));
    canvas->drawPath(body, fill_paint(bezel->body.fill));
    canvas->drawPath(body, stroke_paint(bezel->body.stroke, stroke_width));
    draw_hardware_controls(canvas, *bezel, layout.canvas);
}

bool draw_shaped_button_label(SkCanvas *canvas, otter::RasterCanvas &font_source, const CanvasRect &button, const Rgba &color) {
    otter::FontOptions font_options;
    font_options.family = "Noto Sans";
    font_options.size = kChromeButtonLabelFontSize;

    otter::TextLine line;
    std::string error_message;
    if (!otter::shape_text(font_source, kChromeButtonLabel, font_options, "", &line, &error_message) || !line.blob) {
        return false;
    }

    SkPaint paint = fill_paint(color);
    const float x = static_cast<float>(button.x) + std::max(0.0f, (static_cast<float>(button.width) - line.metrics.width) / 2.0f);
    const float y = static_cast<float>(button.y) + std::max(0.0f, (static_cast<float>(button.height) - line.metrics.height) / 2.0f);
    canvas->drawTextBlob(line.blob, x, y + line.metrics.height, paint);
    return true;
}

void draw_simple_button_label(SkCanvas *canvas, const CanvasRect &button, const Rgba &color) {
    SkFont font(nullptr, kChromeButtonLabelFontSize);
    font.setEdging(SkFont::Edging::kAntiAlias);

    SkPaint paint = fill_paint(color);
    SkRect bounds;
    const std::size_t label_size = std::strlen(kChromeButtonLabel);
    font.measureText(kChromeButtonLabel, label_size, SkTextEncoding::kUTF8, &bounds);
    const float x = static_cast<float>(button.x) + ((static_cast<float>(button.width) - bounds.width()) / 2.0f) - bounds.left();
    const float y = static_cast<float>(button.y) + ((static_cast<float>(button.height) - bounds.height()) / 2.0f) - bounds.top();
    canvas->drawSimpleText(kChromeButtonLabel, label_size, SkTextEncoding::kUTF8, x, y, font, paint);
}

void draw_chrome_button(SkCanvas *canvas, otter::RasterCanvas &font_source, const CanvasRect &button, const ButtonStyle &style) {
    const SkRect rect = sk_rect(button);
    canvas->drawRect(rect, fill_paint(style.background));
    canvas->drawRect(rect, stroke_paint(style.border, 1.0f));
    if (!draw_shaped_button_label(canvas, font_source, button, style.label)) {
        draw_simple_button_label(canvas, button, style.label);
    }
}

bool render_chrome(SDL_Renderer *renderer, otter::RasterCanvas &font_source, const ChromeLayout &layout, const ButtonInteraction &button_interaction) {
    int output_width = 0;
    int output_height = 0;
    if (SDL_GetRendererOutputSize(renderer, &output_width, &output_height) != 0 || output_width <= 0 || output_height <= 0) {
        return false;
    }

    const SkImageInfo info = SkImageInfo::Make(
        output_width,
        output_height,
        kRGBA_8888_SkColorType,
        kPremul_SkAlphaType);
    sk_sp<SkSurface> surface = SkSurfaces::Raster(info);
    if (!surface) {
        return false;
    }

    SkCanvas *chrome = surface->getCanvas();
    chrome->clear(SK_ColorTRANSPARENT);
    draw_device_bezel(chrome, layout);
    draw_chrome_button(chrome, font_source, layout.button, button_style(button_interaction));

    SkPixmap pixmap;
    if (!surface->peekPixels(&pixmap)) {
        return false;
    }

    SDL_Texture *texture = SDL_CreateTexture(
        renderer,
        SDL_PIXELFORMAT_RGBA32,
        SDL_TEXTUREACCESS_STATIC,
        output_width,
        output_height);
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
    const SDL_Rect destination = {0, 0, output_width, output_height};
    if (ok && SDL_RenderCopy(renderer, texture, nullptr, &destination) != 0) {
        ok = false;
    }
    SDL_DestroyTexture(texture);
    return ok;
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
    const BezelSpec *bezel,
    const otter::RasterCanvas &canvas,
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
    *hit = chrome_button_hit(bezel, output_width, output_height, canvas.width(), canvas.height(), output_x, output_y);
    return true;
}

bool present_canvas(
    SDL_Renderer *renderer,
    SDL_Texture *texture,
    const BezelSpec *bezel,
    otter::RasterCanvas &canvas,
    const ButtonInteraction &button_interaction) {
    std::vector<std::uint8_t> rgba;
    otter::canvas_to_rgba32(canvas, &rgba);

    if (SDL_UpdateTexture(texture, nullptr, rgba.data(), canvas.width() * 4) != 0) {
        return false;
    }

    int output_width = 0;
    int output_height = 0;
    if (SDL_GetRendererOutputSize(renderer, &output_width, &output_height) != 0) {
        return false;
    }
    const ChromeLayout layout = chrome_layout(bezel, output_width, output_height, canvas.width(), canvas.height());
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
    const BezelSpec *bezel,
    otter::RasterCanvas &canvas,
    const ButtonInteraction &button_interaction) {
    if (!present_canvas(renderer, texture, bezel, canvas, button_interaction)) {
        panic_sdl("SDL present", texture, renderer, window, sdl_initialized);
    }
}

void run_event_loop(
    SDL_Texture *texture,
    SDL_Renderer *renderer,
    SDL_Window *window,
    bool sdl_initialized,
    const BezelSpec *bezel,
    otter::RasterCanvas &canvas,
    ButtonInteraction button_interaction) {
    bool running = true;
    bool press_started_on_button = false;

    auto redraw_if_changed = [&](bool hovered, bool pressed) {
        if (update_button_interaction(&button_interaction, hovered, pressed)) {
            redraw_canvas(texture, renderer, window, sdl_initialized, bezel, canvas, button_interaction);
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
                if (!button_hit_for_window_point(renderer, window, bezel, canvas, event.motion.x, event.motion.y, &hit)) {
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
                    if (!button_hit_for_window_point(renderer, window, bezel, canvas, event.button.x, event.button.y, &hit)) {
                        panic_sdl("SDL_GetRendererOutputSize", texture, renderer, window, sdl_initialized);
                    }
                    press_started_on_button = hit;
                    redraw_if_changed(hit, hit);
                }
                break;
            case SDL_MOUSEBUTTONUP:
                if (event.button.button == SDL_BUTTON_LEFT) {
                    bool hit = false;
                    if (!button_hit_for_window_point(renderer, window, bezel, canvas, event.button.x, event.button.y, &hit)) {
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
                    redraw_canvas(texture, renderer, window, sdl_initialized, bezel, canvas, button_interaction);
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
    otter::RasterCanvas *canvas = otter::binding::get_canvas(argv, 0);
    Janet options = argc >= 2 ? argv[1] : janet_wrap_nil();
    const bool block = option_bool(options, "block?", true);
    const BezelSpec *bezel = selected_bezel_spec();
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
    std::fprintf(stderr, "Otter SDL bezel: %s\n", bezel_id(bezel));

    window = SDL_CreateWindow(
        "Otter",
        SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED,
        chrome_window_width(bezel, canvas->width()),
        chrome_window_height(bezel, canvas->height()),
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
    if (!present_canvas(renderer, texture, bezel, *canvas, button_interaction)) {
        panic_sdl("SDL present", texture, renderer, window, sdl_initialized);
    }

    if (block) {
        run_event_loop(texture, renderer, window, sdl_initialized, bezel, *canvas, button_interaction);
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
        "Open an SDL window, present a raster canvas with desktop diagnostics chrome, and optionally run the static event loop."
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    otter::binding::register_common_cfuns(env, "skia");
    janet_cfuns(env, "skia", platform_cfuns);
}
