PKG_CONFIG ?= pkg-config
CXX ?= c++

BUILD_DIR := build
NATIVE_MODULE := $(BUILD_DIR)/janet-otter-sdl.so
SDL_PC ?= $(shell if command -v $(PKG_CONFIG) >/dev/null 2>&1 && $(PKG_CONFIG) --exists sdl2; then printf sdl2; elif command -v $(PKG_CONFIG) >/dev/null 2>&1 && $(PKG_CONFIG) --exists sdl2-compat; then printf sdl2-compat; else printf sdl2; fi)
PC_MODULES := janet skia $(SDL_PC)
comma := ,

WARN_CXXFLAGS := -std=c++17 -Wall -Wextra -fPIC
OPT_CXXFLAGS ?= -O2 -g
PC_CFLAGS = $(shell $(PKG_CONFIG) --cflags $(PC_MODULES))
PC_LIBS = $(shell $(PKG_CONFIG) --libs $(PC_MODULES))
PC_RPATHS = $(patsubst -L%,-Wl$(comma)-rpath$(comma)%,$(shell $(PKG_CONFIG) --libs-only-L $(PC_MODULES)))

.PHONY: native test run clean

native: $(NATIVE_MODULE)

$(NATIVE_MODULE): src/janet_otter_sdl.cc src/otter_skia_hello.cc src/otter_skia_hello.hh
	mkdir -p $(BUILD_DIR)
	$(CXX) $(WARN_CXXFLAGS) $(OPT_CXXFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(PC_CFLAGS) \
		-shared -o $@ \
		src/janet_otter_sdl.cc src/otter_skia_hello.cc \
		$(LDFLAGS) $(PC_RPATHS) $(PC_LIBS)

test: $(NATIVE_MODULE)
	OTTER_DESKTOP_NATIVE="$(abspath $(NATIVE_MODULE))" jeep test

run: $(NATIVE_MODULE)
	OTTER_DESKTOP_NATIVE="$(abspath $(NATIVE_MODULE))" ./bin/otter

clean:
	rm -rf $(BUILD_DIR)
