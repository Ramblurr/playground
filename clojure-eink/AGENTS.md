# Clojure e-ink PoC agent notes

## Project shape

- Goal: prove out Clojure/JVM e-reader software for 32-bit ARM e-ink devices, starting with Kobo.
- Current working path: Clojure + Java2D grayscale `BufferedImage` + Java FFM + native FBInk bridge -> framebuffer.
- UI exploration: Membrane is being proven as the UI framework with a custom Java2D/FBInk backend. A later parallel track may compare Membrane + Skia.
- Cold JVM startup is slow; long-lived JVM loops and warm rendering are acceptable and expected.
- Current best warm path uses cached layout/reused images; see `STATUS.md` and `PERF_NOTES.md` for timings.
- Current task context is in `prompts/006-membrane-components-ui-prep.md`; older render context is in `prompts/001-render-task.md`.

## Source ownership

- `src/clj/membrane/` is vendored upstream Membrane only. Do not edit files there by hand.
- When vendoring Membrane, copy exact files from `/home/ramblurr/src/github.com/phronmophobic/membrane/src/membrane/` with `cp`, then verify with `diff -q`.
- Local backend code belongs under `src/clj/ol/membrane/backend/`, currently `ol.membrane.backend.java2d` and `ol.membrane.backend.skia`.
- Demo/proof UI belongs under `src/clj/ol/*`, currently `ol.membrane-demo` and future `ol.membrane-demo.*`.
- Do not overwrite `dev/user.clj`.
- Unrelated Nix/package work may be present in the worktree; do not stage or modify it unless explicitly asked.
- Never bypass npm `ignore-scripts` unless explicitly instructed.

## Local commands

```sh
bb test
clojure -M:kaocha
clojure -T:build jar
scripts/package-kobo-dist.sh
```

Useful local Membrane smoke:

```sh
clojure -M -m ol.membrane-demo --no-present --width 320 --height 240 --png target/membrane-demo.png
printf 'render\nrender\nquit\n' | clojure -M -m ol.membrane-demo --loop --no-present --width 320 --height 240
```

## Kobo device

- SSH host: `kobo-lan` (`root@kobo-lan`).
- Deployed app path: `/mnt/onboard/clojure-eink-demo`.
- Kobo JDK path: `/nix/kobo-jdk25-clojure-fast-uberwarm-ffm-java2d`.
- Native bridge in dist: `lib/libclojure_eink.so`.
- Use safe rsync flags:

```sh
rsync -rtv --delete --no-owner --no-group --no-perms target/dist/ \
  root@kobo-lan:/mnt/onboard/clojure-eink-demo/
```

## Kobo run commands

Run on the Kobo in `/mnt/onboard/clojure-eink-demo`:

(ONLY use tmux/tmuxb for this, see below)

```sh
./run-demo.sh --renders 5 --present-last --render-mode cached-layout
./run-loop.sh --render-mode cached-layout --reuse-image --no-wait --no-flash
./run-membrane-demo.sh --no-wait --no-flash
printf 'render\nrender\nquit\n' | ./run-membrane-loop.sh --no-wait --no-flash
```

Loop commands:

```text
render [options]
reload
help
quit
```

## tmux / device interaction

- A `tmuxb` session named `clojure-eink` is used for interactive Kobo work.
- Always run `tmuxb capture` before `tmuxb send`.
- Do not send blind commands into an unknown shell, quote continuation, heredoc, or running loop.
- Example:

```sh
tmuxb capture
tmuxb send -- '"cd /mnt/onboard/clojure-eink-demo" :Enter'
tmuxb send -- '"./run-membrane-demo.sh --no-wait --no-flash" :Enter'
tmuxb capture
```

Screenshot only after meaningful visual changes:

```sh
bash screenshot.sh
```


## Reference material

Out of repo reference material:

- ~/src/github.com/koreader/koreader
- ~/src/github.com/phronmophobic/membrane/
- ~/src/github.com/HumbleUI/Skija
- ~/src/github.com/google/skia

Also see extra/
