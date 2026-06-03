# Janet e-ink agent notes

## Goal

- Run Janet on Kobo ARMv7l and iterate toward e-ink UI demos.
- Target host: `root@kobo-lan`.
- Target install dir: `/mnt/onboard/janet-eink-demo/janet`.

## Nix outputs

- `.#janet-armv7l` — cross-built `pkgs.janet` for ARMv7l.
- `.#fbink-kobo` — Kobo FBInk build copied from `../clojure-eink` pattern.
- `.#janet-fbink-bridge-kobo` — legacy Janet native module exposing simple FBInk text calls; not bundled by default.
- `.#janet-skia-bridge-kobo` — Janet native module exposing gray8 Skia drawing primitives and presenting via FBInk.
- `.#skia-kobo` — ARMv7l Skia raster/text libs copied from `../clojure-eink`.
- `.#kobo-bundle` — self-contained Kobo runtime bundle of everything.
- `.#janet-otter-sdl` — local x86_64 Janet native module drawing gray8 Skia canvases and presenting through SDL.

## Code map

- `bin/otter` — Janet entrypoint; loads source modules or installed bundle modules.
- `lib/skia.janet` — the single public Janet drawing API for canvases, primitives, text, PNG images, and presentation delegation.
- `lib/platform.janet` — chooses `:desktop-sdl` on Linux dev hosts and `:kobo-fbink` on Kobo.
- `lib/platform/desktop.janet` — narrow SDL provider: native loading, screen size, presentation, and desktop helpers.
- `lib/platform/kobo.janet` — narrow Kobo provider: native loading, framebuffer size, and FBInk presentation.
- `lib/demo/shapes.janet` — Janet-owned grayscale geometry demo using `lib/skia.janet`.
- `src/otter_drawing_backend.*` — shared gray8 Skia drawing backend for rectangles, rounded rectangles, paths, images, text, stats, and RGBA conversion.
- `src/janet_otter_sdl.cc` — SDL desktop presenter; registers common drawing bindings and presents a portrait `1264x1680` Kobo canvas at half size (`632x840`) centered in the compositor window, clipping when needed.
- `src/janet_skia.cc` — Kobo presenter; registers common drawing bindings and presents gray8 buffers via FBInk.

## Bundle shape

Installed as:

```text
/mnt/onboard/janet-eink-demo/janet/{bin,include,lib,share}
```

Important files:

- `bin/janet`
- `bin/otter`
- `lib/janet-skia.so`
- `lib/libfbink.so.1`
- `lib/libskia.so`, `lib/libskparagraph.so`, `lib/libskshaper.so`, `libskunicode_*`
- `otter/{init.janet,lib/*.janet}`
- `share/janet-eink/demo-skia.janet`

`nix/pkgs/janet-kobo-bundle/package.nix` accepts:

- `bundledNativeLibPackages = [ ... ];`
- `bundledTreePackages = [ ... ];`
- `bundledJanetBundles = [{ name = "..."; src = ./...; }];` — installed with target Janet under qemu so bundle metadata is present.
- `bundledPrograms = [{ name = "..."; src = ./...; destination = "..."; mode = "0644"; }];` for loose extra files only.

It copies ELF libs by SONAME as real files because `/mnt/onboard` does not support symlinks.

## Kobo Build/install

```sh
./install.sh
```

The script builds `.#kobo-bundle` to a temp out-link, then rsyncs to Kobo with safe flags.

Smoke checks:

```sh
ssh root@kobo-lan 'cd /mnt/onboard/janet-eink-demo/janet && ./bin/janet -v'
ssh root@kobo-lan 'cd /mnt/onboard/janet-eink-demo/janet && ./bin/janet share/janet-eink/demo-skia.janet'
ssh root@kobo-lan 'cd /mnt/onboard/janet-eink-demo/janet && PATH="$PWD/bin:$PATH" ./bin/otter'
```

Expected Skia/FBInk smoke exits `0` and renders a full-screen grayscale geometry demo with bars, rectangles, triangles, rounded rectangles, circles, and a black border.

## Kobo Run/Dev

```
cd /mnt/onboard/janet-eink-demo/janet
export PATH="$PWD/bin:$PATH"
./bin/otter
```

## Local Dev

Enter:

```sh
nix develop
```

Dev shell tools: `janet`, `jpm`, `gcc`, `make`, `pkg-config`, `SDL2`, `skia`, `jeep`.

Run Otter from source:

```sh
make native
./bin/otter
```

Install/run as a local modern bundle:

```sh
jeep -l install
./_system/bin/otter
```

Testing:
```sh
jeep test
```

Deps are vendored:
```sh
jeep dep --vendor <dep>
jeep prep vendor
```

## Local netrepl

Spork script reference:

```text
/home/ramblurr/src/github.com/janet-lang/spork/bin/janet-netrepl
```

Start local server:

```sh
nix develop
janet-netrepl -s -H 127.0.0.1 -P 9365
```

Client smoke:

```sh
printf '(+ 20 22)\n' | janet-netrepl -c -H 127.0.0.1 -P 9365 -n smoke
```

A local server was started during setup:

- host: `127.0.0.1`
- port: `9365`
- pid file: `.netrepl-local.pid`
- log: `.netrepl-local.log`

Editor should connect to Janet netrepl, **not nREPL**, at `127.0.0.1:9365`.

## Kobo netrepl

Spork netrepl is packaged for Kobo as `.#spork-netrepl-kobo` and included in `.#kobo-bundle`.

Bundled files:

- `bin/janet-netrepl`
- `share/janet/spork/{argparse,ev-utils,generators,getline,msg,netrepl}.janet`
- `share/janet/spork/rawterm.so`

Start on Kobo:

```sh
ssh root@kobo-lan 'cd /mnt/onboard/janet-eink-demo/janet && \
  nohup ./bin/janet-netrepl -s -H 0.0.0.0 -P 9365 -m "Kobo Janet netrepl" \
    > netrepl.log 2>&1 < /dev/null & echo $! > netrepl.pid'
```

Stop on Kobo:

```sh
ssh root@kobo-lan 'cd /mnt/onboard/janet-eink-demo/janet && kill $(cat netrepl.pid)'
```

Local client smoke:

```sh
KOBO_HOST=$(ssh -G kobo-lan | awk '/^hostname /{print $2; exit}')
printf '(+ 40 2)\n' | janet-netrepl -c -H "$KOBO_HOST" -P 9365 -n smoke
```

`kobo-lan` is an SSH alias; Janet netrepl needs the resolved host/IP unless DNS also knows `kobo-lan`.

## Reference

- janet  ~/src/github.com/janet-lang/janet
- janet spork (official contrib library) ~/src/github.com/janet-lang/spork
- janet docs/site ~/src/github.com/janet-lang/janet-lang.org
- skia ~/src/github.com/google/skia
- membrane ~/src/github.com/phronmophobic/membrane
- extra/ local repo reference material
    - janet-bundles.md how janet bundles work
    - janet-dir-structure.md how janet dir structure works
