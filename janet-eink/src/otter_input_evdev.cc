#include "otter_input_evdev.hh"

#include <cerrno>
#include <climits>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace otter::input {
namespace {

struct InputHandle {
    int fd = -1;
    bool grabbed = false;
    std::string path;
    std::string name;
    std::string source_kind = "evdev";
    std::uint32_t device_type = 0;
};

std::vector<InputHandle *> open_handles;

Janet keyword(const char *name) {
    return janet_ckeywordv(name);
}

bool dictionary_like(Janet value) {
    return janet_checktype(value, JANET_TABLE) || janet_checktype(value, JANET_STRUCT);
}

Janet option_value(Janet options, const char *key) {
    if (!dictionary_like(options)) {
        return janet_wrap_nil();
    }
    return janet_get(options, keyword(key));
}

bool option_bool(Janet options, const char *key, bool default_value) {
    Janet value = option_value(options, key);
    if (janet_checktype(value, JANET_NIL)) {
        return default_value;
    }
    if (!janet_checktype(value, JANET_BOOLEAN)) {
        janet_panicf("input option :%s must be a boolean", key);
    }
    return janet_unwrap_boolean(value);
}

bool env_disables_grab() {
    const char *value = std::getenv("OTTER_DONT_GRAB_INPUT");
    return value != nullptr && value[0] != '\0' && std::strcmp(value, "0") != 0;
}

bool should_grab(Janet options) {
    return !env_disables_grab() && option_bool(options, "grab?", false);
}

void remove_open_handle(InputHandle *handle) {
    for (std::size_t i = 0; i < open_handles.size(); ++i) {
        if (open_handles[i] == handle) {
            open_handles.erase(open_handles.begin() + static_cast<std::ptrdiff_t>(i));
            return;
        }
    }
}

void close_handle(InputHandle *handle) {
    if (handle == nullptr) {
        return;
    }
    if (handle->fd >= 0) {
        if (handle->grabbed) {
            ioctl(handle->fd, EVIOCGRAB, 0);
            handle->grabbed = false;
        }
        close(handle->fd);
        handle->fd = -1;
    }
    remove_open_handle(handle);
}

int handle_gc(void *p, size_t s) {
    (void) s;
    auto *handle = static_cast<InputHandle *>(p);
    close_handle(handle);
    handle->~InputHandle();
    return 0;
}

const JanetAbstractType handle_type = {
    "otter/input-handle",
    handle_gc,
    nullptr,
    nullptr,
    nullptr,
    JANET_ATEND_PUT
};

InputHandle *get_handle(Janet *argv, int32_t n) {
    return static_cast<InputHandle *>(janet_getabstract(argv, n, &handle_type));
}

Janet make_error_result(const char *operation, int error) {
    JanetTable *table = janet_table(3);
    janet_table_put(table, keyword("error"), janet_wrap_integer(error));
    janet_table_put(table, keyword("operation"), janet_cstringv(operation));
    janet_table_put(table, keyword("message"), janet_cstringv(std::strerror(error)));
    return janet_wrap_table(table);
}

Janet make_timeout_result() {
    JanetTable *table = janet_table(2);
    janet_table_put(table, keyword("timeout?"), janet_wrap_true());
    janet_table_put(table, keyword("events"), janet_wrap_array(janet_array(0)));
    return janet_wrap_table(table);
}

Janet make_ok_result(JanetArray *events) {
    JanetTable *table = janet_table(2);
    janet_table_put(table, keyword("ok?"), janet_wrap_true());
    janet_table_put(table, keyword("events"), janet_wrap_array(events));
    return janet_wrap_table(table);
}

Janet make_source_table(const InputHandle &handle) {
    JanetTable *source = janet_table(5);
    janet_table_put(source, keyword("kind"), keyword(handle.source_kind.c_str()));
    janet_table_put(source, keyword("fd"), janet_wrap_integer(handle.fd));
    janet_table_put(source, keyword("path"), janet_cstringv(handle.path.c_str()));
    if (!handle.name.empty()) {
        janet_table_put(source, keyword("name"), janet_cstringv(handle.name.c_str()));
    }
    if (handle.device_type != 0) {
        janet_table_put(source, keyword("device-type"), janet_wrap_integer(static_cast<std::int32_t>(handle.device_type)));
    }
    return janet_wrap_table(source);
}

Janet make_time_table(const struct input_event &event) {
    JanetTable *time = janet_table(2);
    janet_table_put(time, keyword("sec"), janet_wrap_number(static_cast<double>(event.input_event_sec)));
    janet_table_put(time, keyword("usec"), janet_wrap_number(static_cast<double>(event.input_event_usec)));
    return janet_wrap_table(time);
}

Janet make_event_record(const InputHandle &handle, const struct input_event &event) {
    JanetTable *record = janet_table(5);
    janet_table_put(record, keyword("type"), janet_wrap_integer(event.type));
    janet_table_put(record, keyword("code"), janet_wrap_integer(event.code));
    janet_table_put(record, keyword("value"), janet_wrap_integer(event.value));
    janet_table_put(record, keyword("time"), make_time_table(event));
    janet_table_put(record, keyword("source"), make_source_table(handle));
    return janet_wrap_table(record);
}

std::string evdev_name(int fd) {
    char name[256];
    std::memset(name, 0, sizeof(name));
    if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) < 0) {
        return std::string();
    }
    return std::string(name);
}

bool set_nonblocking_cloexec(int fd, const char *operation, Janet *error_out) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) {
        *error_out = make_error_result(operation, errno ? errno : EIO);
        return false;
    }
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
        *error_out = make_error_result(operation, errno ? errno : EIO);
        return false;
    }

    int fd_flags = fcntl(fd, F_GETFD, 0);
    if (fd_flags < 0) {
        *error_out = make_error_result(operation, errno ? errno : EIO);
        return false;
    }
    if (fcntl(fd, F_SETFD, fd_flags | FD_CLOEXEC) < 0) {
        *error_out = make_error_result(operation, errno ? errno : EIO);
        return false;
    }
    return true;
}

}  // namespace

Janet adopt_evdev_fd(
    int fd,
    const char *path,
    Janet options,
    const char *source_kind,
    const char *name,
    std::uint32_t device_type) {
    Janet error = janet_wrap_nil();
    if (!set_nonblocking_cloexec(fd, "fcntl", &error)) {
        close(fd);
        return error;
    }

    const bool grab = should_grab(options);
    if (grab && ioctl(fd, EVIOCGRAB, 1) < 0) {
        const int saved = errno ? errno : EIO;
        close(fd);
        return make_error_result("EVIOCGRAB", saved);
    }

    void *memory = janet_abstract(&handle_type, sizeof(InputHandle));
    auto *handle = new (memory) InputHandle();
    handle->fd = fd;
    handle->grabbed = grab;
    handle->path = path != nullptr ? path : "";
    handle->name = name != nullptr && name[0] != '\0' ? name : evdev_name(fd);
    handle->source_kind = source_kind != nullptr && source_kind[0] != '\0' ? source_kind : "evdev";
    handle->device_type = device_type;

    open_handles.push_back(handle);
    return janet_wrap_abstract(handle);
}

namespace {

std::vector<InputHandle *> active_handles() {
    std::vector<InputHandle *> handles;
    handles.reserve(open_handles.size());
    for (InputHandle *handle : open_handles) {
        if (handle != nullptr && handle->fd >= 0) {
            handles.push_back(handle);
        }
    }
    return handles;
}

Janet cfun_input_open(int32_t argc, Janet *argv) {
    janet_arity(argc, 1, 2);
    const char *path = janet_getcstring(argv, 0);
    Janet options = argc >= 2 ? argv[1] : janet_wrap_nil();
    const int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        return make_error_result("open", errno ? errno : EIO);
    }
    return adopt_evdev_fd(fd, path, options);
}

Janet cfun_input_fdopen(int32_t argc, Janet *argv) {
    janet_arity(argc, 2, 3);
    const int fd = janet_getinteger(argv, 0);
    const char *path = janet_getcstring(argv, 1);
    if (fd < 0) {
        return make_error_result("fdopen", EBADF);
    }
    Janet options = argc >= 3 ? argv[2] : janet_wrap_nil();
    return adopt_evdev_fd(fd, path, options);
}

Janet cfun_input_close(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    InputHandle *handle = get_handle(argv, 0);
    close_handle(handle);
    return janet_wrap_true();
}

Janet cfun_input_close_all(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 0);
    (void) argv;
    int32_t closed = 0;
    while (!open_handles.empty()) {
        InputHandle *handle = open_handles.back();
        if (handle != nullptr && handle->fd >= 0) {
            ++closed;
        }
        close_handle(handle);
    }
    return janet_wrap_integer(closed);
}

Janet cfun_input_wait_event(int32_t argc, Janet *argv) {
    janet_arity(argc, 1, 2);
    int timeout_ms = janet_getinteger(argv, 0);
    if (timeout_ms < -1) {
        janet_panic("input-wait-event timeout must be -1 or a non-negative integer number of milliseconds");
    }
    int max_events = argc >= 2 ? janet_getinteger(argv, 1) : 256;
    if (max_events <= 0) {
        janet_panic("input-wait-event max-events must be positive");
    }

    std::vector<InputHandle *> handles = active_handles();
    if (handles.empty()) {
        return make_timeout_result();
    }

    std::vector<pollfd> fds;
    fds.reserve(handles.size());
    for (InputHandle *handle : handles) {
        pollfd pfd;
        pfd.fd = handle->fd;
        pfd.events = POLLIN;
        pfd.revents = 0;
        fds.push_back(pfd);
    }

    int rv;
    do {
        rv = poll(fds.data(), fds.size(), timeout_ms);
    } while (rv < 0 && errno == EINTR);

    if (rv == 0) {
        return make_timeout_result();
    }
    if (rv < 0) {
        return make_error_result("poll", errno ? errno : EIO);
    }

    JanetArray *events = janet_array(0);
    for (std::size_t i = 0; i < fds.size() && events->count < max_events; ++i) {
        InputHandle *handle = handles[i];
        const short revents = fds[i].revents;
        if ((revents & (POLLIN | POLLERR | POLLHUP | POLLNVAL)) == 0) {
            continue;
        }
        if ((revents & POLLNVAL) != 0) {
            close_handle(handle);
            return make_error_result("poll input fd", ENODEV);
        }

        for (;;) {
            struct input_event event;
            const ssize_t n = read(handle->fd, &event, sizeof(event));
            if (n == static_cast<ssize_t>(sizeof(event))) {
                janet_array_push(events, make_event_record(*handle, event));
                if (events->count >= max_events) {
                    return make_ok_result(events);
                }
                continue;
            }
            if (n < 0 && errno == EINTR) {
                continue;
            }
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                break;
            }
            if (n < 0 && errno == ENODEV) {
                close_handle(handle);
                return make_error_result("read input fd", ENODEV);
            }
            if (n == 0) {
                return make_error_result("read input fd", EPIPE);
            }
            return make_error_result("read input fd", n < 0 ? (errno ? errno : EIO) : EINVAL);
        }
    }

    if (events->count == 0) {
        return make_timeout_result();
    }
    return make_ok_result(events);
}

const JanetReg evdev_cfuns[] = {
    {
        "input-open", cfun_input_open,
        "(input-open path &opt options)\n\n"
        "Open a Linux evdev path nonblocking with close-on-exec behavior."
    },
    {
        "input-fdopen", cfun_input_fdopen,
        "(input-fdopen fd path &opt options)\n\n"
        "Adopt an existing evdev file descriptor."
    },
    {
        "input-close", cfun_input_close,
        "(input-close handle)\n\nClose an input handle."
    },
    {
        "input-close-all", cfun_input_close_all,
        "(input-close-all)\n\nClose all open input handles."
    },
    {
        "input-wait-event", cfun_input_wait_event,
        "(input-wait-event timeout-ms &opt max-events)\n\n"
        "Poll open input handles and return a raw event batch, a timeout, or an error table."
    },
    {NULL, NULL, NULL}
};

}  // namespace

void register_evdev_cfuns(JanetTable *env, const char *prefix) {
    janet_cfuns(env, prefix, evdev_cfuns);
}

}  // namespace otter::input
