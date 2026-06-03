#include <cerrno>
#include <climits>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <janet.h>
#include "fbink.h"

#include "janet_skia_common.hh"
#include "otter_drawing_backend.hh"
#include "otter_input_evdev.hh"

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

Janet keyword(const char *name) {
    return janet_ckeywordv(name);
}

Janet make_error_result(const char *operation, int error) {
    JanetTable *table = janet_table(3);
    janet_table_put(table, keyword("error"), janet_wrap_integer(error));
    janet_table_put(table, keyword("operation"), janet_cstringv(operation));
    janet_table_put(table, keyword("message"), janet_cstringv(std::strerror(error)));
    return janet_wrap_table(table);
}

Janet make_scan_result(const char *method, JanetArray *handles) {
    JanetTable *table = janet_table(3);
    janet_table_put(table, keyword("ok?"), janet_wrap_true());
    janet_table_put(table, keyword("method"), keyword(method));
    janet_table_put(table, keyword("handles"), janet_wrap_array(handles));
    janet_table_put(table, keyword("count"), janet_wrap_integer(handles->count));
    return janet_wrap_table(table);
}

void close_fbink_scan_devices(FBInkInputDevice *devices, std::size_t count) {
    if (devices == nullptr) {
        return;
    }
    for (std::size_t i = 0; i < count; ++i) {
        if (devices[i].fd >= 0) {
            close(devices[i].fd);
            devices[i].fd = -1;
        }
    }
}

void push_if_handle(JanetArray *handles, Janet value) {
    if (janet_checktype(value, JANET_ABSTRACT)) {
        janet_array_push(handles, value);
    }
}

bool open_path_for_adoption(const char *path, int *fd_out) {
    const int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        return false;
    }
    *fd_out = fd;
    return true;
}

constexpr std::size_t bits_per_word() {
    return sizeof(unsigned long) * CHAR_BIT;
}

std::size_t words_for_bit(int max_bit) {
    return (static_cast<std::size_t>(max_bit) + bits_per_word()) / bits_per_word();
}

bool test_bit(const std::vector<unsigned long> &bits, int bit) {
    const std::size_t word = static_cast<std::size_t>(bit) / bits_per_word();
    const std::size_t offset = static_cast<std::size_t>(bit) % bits_per_word();
    return word < bits.size() && ((bits[word] >> offset) & 1UL) != 0;
}

bool read_bits(int fd, int ev, int max_bit, std::vector<unsigned long> *bits) {
    bits->assign(words_for_bit(max_bit), 0);
    return ioctl(fd, EVIOCGBIT(ev, static_cast<int>(bits->size() * sizeof(unsigned long))), bits->data()) >= 0;
}

bool has_abs_info(int fd, int code) {
    struct input_absinfo abs;
    std::memset(&abs, 0, sizeof(abs));
    return ioctl(fd, EVIOCGABS(code), &abs) >= 0;
}

std::string ioctl_device_name(int fd) {
    char name[256];
    std::memset(name, 0, sizeof(name));
    if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) < 0) {
        return std::string();
    }
    return std::string(name);
}

std::uint32_t classify_ioctl_input(int fd) {
    std::vector<unsigned long> key_bits;
    std::vector<unsigned long> abs_bits;
    const bool have_keys = read_bits(fd, EV_KEY, KEY_MAX, &key_bits);
    const bool have_abs = read_bits(fd, EV_ABS, ABS_MAX, &abs_bits);

    std::uint32_t type = INPUT_UNKNOWN;
    if (have_abs &&
        ((test_bit(abs_bits, ABS_MT_POSITION_X) && test_bit(abs_bits, ABS_MT_POSITION_Y)) ||
         (test_bit(abs_bits, ABS_X) && test_bit(abs_bits, ABS_Y)) ||
         has_abs_info(fd, ABS_MT_POSITION_X) ||
         has_abs_info(fd, ABS_X))) {
        type |= INPUT_TOUCHSCREEN;
    }
    if (have_keys) {
        if (test_bit(key_bits, KEY_POWER)) {
            type |= INPUT_POWER_BUTTON;
        }
        if (test_bit(key_bits, 35) || test_bit(key_bits, 59)) {
            type |= INPUT_SLEEP_COVER;
        }
        if (test_bit(key_bits, 193) || test_bit(key_bits, 194)) {
            type |= INPUT_PAGINATION_BUTTONS;
        }
        if (test_bit(key_bits, 90)) {
            type |= INPUT_LIGHT_BUTTON;
        }
    }
    return type;
}

JanetArray *open_ioctl_scan(Janet options) {
    JanetArray *handles = janet_array(0);
    constexpr std::uint32_t desired = INPUT_TOUCHSCREEN | INPUT_TABLET | INPUT_POWER_BUTTON | INPUT_SLEEP_COVER | INPUT_PAGINATION_BUTTONS | INPUT_LIGHT_BUTTON;
    for (int index = 0; index < 32; ++index) {
        char path[64];
        std::snprintf(path, sizeof(path), "/dev/input/event%d", index);
        int fd = -1;
        if (!open_path_for_adoption(path, &fd)) {
            continue;
        }
        const std::uint32_t device_type = classify_ioctl_input(fd);
        if ((device_type & desired) == 0) {
            close(fd);
            continue;
        }
        const std::string name = ioctl_device_name(fd);
        Janet handle = otter::input::adopt_evdev_fd(fd, path, options, "kobo-ioctl-scan", name.c_str(), device_type);
        push_if_handle(handles, handle);
    }
    return handles;
}

JanetArray *open_traditional_fallback(Janet options) {
    JanetArray *handles = janet_array(0);
    for (int index = 0; index < 2; ++index) {
        char path[64];
        std::snprintf(path, sizeof(path), "/dev/input/event%d", index);
        int fd = -1;
        if (!open_path_for_adoption(path, &fd)) {
            continue;
        }
        const std::string name = ioctl_device_name(fd);
        Janet handle = otter::input::adopt_evdev_fd(fd, path, options, "kobo-traditional-fallback", name.c_str(), INPUT_UNKNOWN);
        push_if_handle(handles, handle);
    }
    return handles;
}

Janet open_kobo_input_scan(Janet options) {
    std::size_t dev_count = 0;
    constexpr INPUT_DEVICE_TYPE_T match = INPUT_TOUCHSCREEN | INPUT_TABLET | INPUT_POWER_BUTTON | INPUT_SLEEP_COVER | INPUT_PAGINATION_BUTTONS;
    constexpr INPUT_DEVICE_TYPE_T exclude = INPUT_KEYBOARD;
    FBInkInputDevice *devices = fbink_input_scan(match, exclude, NO_RECAP, &dev_count);
    if (devices != nullptr) {
        JanetArray *handles = janet_array(0);
        for (std::size_t i = 0; i < dev_count; ++i) {
            FBInkInputDevice *device = &devices[i];
            if (!device->matched || device->fd < 0) {
                continue;
            }
            Janet handle = otter::input::adopt_evdev_fd(
                device->fd,
                device->path,
                options,
                "kobo-fbink-scan",
                device->name,
                device->type);
            device->fd = -1;
            push_if_handle(handles, handle);
        }
        close_fbink_scan_devices(devices, dev_count);
        std::free(devices);
        if (handles->count > 0) {
            return make_scan_result("fbink", handles);
        }
    }

    JanetArray *ioctl_handles = open_ioctl_scan(options);
    if (ioctl_handles->count > 0) {
        return make_scan_result("ioctl", ioctl_handles);
    }

    JanetArray *fallback_handles = open_traditional_fallback(options);
    if (fallback_handles->count > 0) {
        return make_scan_result("traditional", fallback_handles);
    }

    return make_error_result("input-open-scan", errno ? errno : ENODEV);
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

static Janet cfun_input_open_scan(int32_t argc, Janet *argv) {
    janet_arity(argc, 0, 1);
    Janet options = argc >= 1 ? argv[0] : janet_wrap_nil();
    return open_kobo_input_scan(options);
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
    {
        "input-open-scan", cfun_input_open_scan,
        "(skia/input-open-scan &opt options)\n\n"
        "Open Kobo input devices via FBInk scan, ioctl scan fallback, or traditional event0/event1 fallback."
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    otter::binding::register_common_cfuns(env, "skia");
    otter::input::register_evdev_cfuns(env, "skia");
    janet_cfuns(env, "skia", platform_cfuns);
}
