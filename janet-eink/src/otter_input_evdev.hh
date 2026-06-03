#ifndef OTTER_INPUT_EVDEV_HH
#define OTTER_INPUT_EVDEV_HH

#include <cstdint>

#include <janet.h>

namespace otter::input {

void register_evdev_cfuns(JanetTable *env, const char *prefix);
Janet adopt_evdev_fd(
    int fd,
    const char *path,
    Janet options,
    const char *source_kind = "evdev",
    const char *name = nullptr,
    std::uint32_t device_type = 0);

}  // namespace otter::input

#endif  // OTTER_INPUT_EVDEV_HH
