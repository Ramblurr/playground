# Janet e-ink agent notes

## Goal

- Run Janet on Kobo ARMv7l and iterate toward e-ink UI demos.
- Target host: `root@kobo-lan`.
- Target install dir: `/mnt/onboard/janet-eink-demo/janet`.

## Nix outputs

- `.#janet-armv7l` — cross-built `pkgs.janet` for ARMv7l.
- `.#fbink-kobo` — Kobo FBInk build copied from `../clojure-eink` pattern.
- `.#janet-fbink-bridge-kobo` — Janet native module exposing simple FBInk calls.
- `.#janet-skia-bridge-kobo` — Janet native module rendering the Skia hello demo and presenting via FBInk.
- `.#skia-kobo` — ARMv7l Skia raster/text libs copied from `../clojure-eink`.
- `.#kobo-bundle` — self-contained Kobo runtime bundle of everything
- `.#janet-otter-sdl` — local x86_64 Janet native module presenting the fixed Kobo Skia canvas through SDL.

## Code map

- `bin/otter` — Janet entrypoint; loads source modules or installed bundle modules.
- `lib/platform.janet` — chooses `:desktop-sdl` on Linux dev hosts and `:kobo-fbink` on Kobo.
- `lib/desktop.janet` — Janet wrapper for the SDL native module.
- `lib/kobo.janet` — Janet wrapper for the Kobo Skia/FBInk native module.
- `src/otter_skia_hello.*` — shared Skia software renderer for the hello demo.
- `src/janet_otter_sdl.cc` — SDL desktop backend; opens a window and presents a fixed `1680x1264` Kobo canvas centered in the actual compositor window, clipping rather than scaling.
- `src/janet_skia.cc` — Kobo backend; renders with Skia and presents via FBInk.

## Bundle shape

Installed as:

```text
/mnt/onboard/janet-eink-demo/janet/{bin,include,lib,share}
```

Important files:

- `bin/janet`
- `lib/janet-fbink.so`
- `lib/janet-skia.so`
- `lib/libfbink.so.1`
- `lib/libskia.so`, `lib/libskparagraph.so`, `lib/libskshaper.so`, `libskunicode_*`
- `share/janet-eink/hello-fbink.janet`
- `share/janet-eink/hello-skia.janet`

`nix/pkgs/janet-kobo-bundle/package.nix` accepts:

- `bundledNativeLibPackages = [ ... ];`
- `bundledPrograms = [{ name = "..."; src = ./...; destination = "..."; mode = "0644"; }];`

It copies ELF libs by SONAME as real files because `/mnt/onboard` does not support symlinks.

## Build/install

```sh
./install.sh
```

The script builds `.#kobo-bundle` to a temp out-link, then rsyncs to Kobo with safe flags.

Smoke checks:

```sh
ssh root@kobo-lan 'cd /mnt/onboard/janet-eink-demo/janet && ./bin/janet -v'
ssh root@kobo-lan 'cd /mnt/onboard/janet-eink-demo/janet && ./bin/janet share/janet-eink/hello-fbink.janet'
ssh root@kobo-lan 'cd /mnt/onboard/janet-eink-demo/janet && ./bin/janet share/janet-eink/hello-skia.janet'
```

Expected FBInk smoke exits `0` and prints `Hello Janet!` centered on screen.
Expected Skia smoke exits `0` and renders a white full-screen bitmap with centered black `Hello Skia!` block text and a black rectangle.

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
