#include <errno.h>
#include <stdbool.h>
#include <string.h>

#include <janet.h>
#include "fbink.h"

static Janet cfun_version(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 0);
    (void) argv;
    return janet_cstringv(fbink_version());
}

static Janet cfun_print_centered(int32_t argc, Janet *argv) {
    janet_arity(argc, 0, 1);
    const char *text = argc == 0 ? "Hello Janet!" : janet_getcstring(argv, 0);

    FBInkConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.is_quiet = true;
    cfg.is_centered = true;
    cfg.is_halfway = true;
    cfg.is_cleared = true;

    int fbfd = fbink_open();
    if (fbfd < 0) {
        janet_panicf("fbink_open failed: errno=%d (%s)", errno, strerror(errno));
    }

    int rv = fbink_init(fbfd, &cfg);
    if (rv < 0) {
        int saved = errno;
        fbink_close(fbfd);
        janet_panicf("fbink_init failed: rv=%d errno=%d (%s)", rv, saved, strerror(saved));
    }

    rv = fbink_print(fbfd, text, &cfg);
    if (rv < 0) {
        int saved = errno;
        fbink_close(fbfd);
        janet_panicf("fbink_print failed: rv=%d errno=%d (%s)", rv, saved, strerror(saved));
    }

    int close_rv = fbink_close(fbfd);
    if (close_rv < 0) {
        int saved = errno;
        janet_panicf("fbink_close failed: rv=%d errno=%d (%s)", close_rv, saved, strerror(saved));
    }

    return janet_wrap_integer(rv);
}

static const JanetReg cfuns[] = {
    {
        "version", cfun_version,
        "(fbink/version)\n\n"
        "Return the loaded FBInk library version."
    },
    {
        "print-centered", cfun_print_centered,
        "(fbink/print-centered &opt text)\n\n"
        "Clear the screen and print text horizontally and vertically centered via FBInk."
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    janet_cfuns(env, "fbink", cfuns);
}
