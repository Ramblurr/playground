# Kobo rendering performance notes

## Current result

A long-lived JVM looks viable if we cache text layout work. Cold startup and the first Java2D/font render remain slow, but warm cached renders are well under the sub-1-second goal.

Best measured warm path on Kobo:

```text
long-lived JVM + cached TextLayout + no-wait/no-flash present
render total:    ~27-39 ms
native present:  ~213-221 ms
total warm draw: ~250 ms plus command overhead
```

With normal wait enabled, cached rendering still meets the page-turn target in the measured run:

```text
render total:   ~22 ms
native present: ~793 ms
total:          ~815 ms
```

## Benchmark modes

`ol.project` supports these benchmark options:

```sh
--renders N                 render N times in one JVM
--repeat N                  alias for --renders
--no-present                render and convert to gray8, but do not write to fb0
--present-last              present only the final iteration
--present-each              present every iteration
--render-mode layout        default LineBreakMeasurer path
--render-mode cached-layout cache TextLayout results
--render-mode simple-text   draw strings without LineBreakMeasurer
--render-mode rects         fill rectangle bands, no text
--no-wait                   pass wait=false to native present
--no-flash                  pass flash=false to native present
```

Each render logs phase timings:

- image allocation;
- graphics setup;
- font setup;
- background fill;
- text layout;
- glyph draw;
- total Java2D render;
- image-to-gray8 conversion;
- native present, when enabled.

## Kobo benchmark commands

Deploy from the workstation:

```sh
clojure -T:build jar
cp target/TODO-0.0.TODO.jar target/dist/clojure-eink-demo.jar
rsync -rtv --delete --no-owner --no-group --no-perms target/dist/ \
  root@kobo-lan:/mnt/onboard/clojure-eink-demo/
```

Run on the Kobo:

```sh
cd /mnt/onboard/clojure-eink-demo

time ./run-demo.sh --renders 5 --no-present

time ./run-demo.sh --renders 5 --no-present --render-mode cached-layout

time ./run-demo.sh --renders 5 --present-last --no-wait --no-flash \
  --render-mode cached-layout

time ./run-demo.sh --renders 5 --present-last --render-mode cached-layout
```

## Measurements from 2026-05-31

Screen size: `1264 x 1680`.

### Default layout, render-only

Command:

```sh
time ./run-demo.sh --renders 5 --no-present
```

Observed Java2D totals:

```text
render 1/5: 7033.9 ms
render 2/5: 1138.1 ms
render 3/5: 1080.1 ms
render 4/5:  792.3 ms
render 5/5: 1020.3 ms
```

`LineBreakMeasurer` dominates the warm cost. Re-running layout for the same page is too expensive.

### Cached layout, render-only

Command:

```sh
time ./run-demo.sh --renders 5 --no-present --render-mode cached-layout
```

Observed Java2D totals:

```text
render 1/5: 7004.8 ms
render 2/5:   35.5 ms
render 3/5:   31.9 ms
render 4/5:   39.5 ms
render 5/5:   21.0 ms
```

Caching `TextLayout` removes the main warm bottleneck.

### Cached layout, present final frame, no wait/no flash

Command:

```sh
time ./run-demo.sh --renders 5 --present-last --no-wait --no-flash \
  --render-mode cached-layout
```

Observed final iteration:

```text
render 5/5 Java2D render total: 38.8 ms
render 5/5 native present:      213.1 ms
```

### Cached layout, present final frame, default wait

Command:

```sh
time ./run-demo.sh --renders 5 --present-last --render-mode cached-layout
```

Observed final iteration:

```text
render 5/5 Java2D render total: 22.5 ms
render 5/5 native present:      792.8 ms
```

The default wait path still fits under 1 second once layout is cached.

## Long-lived reload loop

`ol.loop` runs a command loop inside one JVM. It initializes native FBInk once, keeps a layout cache across render commands, and can reload `src/clj/ol/project.clj` without restarting the JVM.

The deployable `target/dist/run-loop.sh` uses this classpath order:

```text
$APP_DIR/src/clj:$CLOJURE_JAR:$APP_DIR/clojure-eink-demo.jar
```

That lets an rsynced source file override the jar copy.

Example on Kobo:

```sh
cd /mnt/onboard/clojure-eink-demo
./run-loop.sh --render-mode cached-layout --no-wait --no-flash
```

Then type commands:

```text
render --renders 1 --no-present
reload
render --renders 1 --present-last
quit
```

`reload` loads this file by default:

```text
/mnt/onboard/clojure-eink-demo/src/clj/ol/project.clj
```

Override it with `EINK_RELOAD_FILE` if needed.

Measured loop behavior:

```text
first cached-layout render command: 7301.0 ms
second cached-layout render command: 27.3 ms
second command with no-wait present: render 34.0 ms, present 220.5 ms
```

After `reload`, the next first render was about `1323.7 ms`; the following render returned to about `34.1 ms`. The JVM, native backend, fonts, and JIT stay warm, but the layout cache is cleared on reload.

## Interpretation

Java2D is not ruled out. The slow path is repeated paragraph layout, not grayscale image allocation, framebuffer conversion, or FBInk presentation. A real reader should avoid recomputing layout for unchanged pages.

Use this direction next:

1. keep a long-lived JVM;
2. cache page layout objects or a page display list;
3. render cached layouts into a reused `BufferedImage`;
4. only recompute layout when content, width, font, margins, or render settings change;
5. use `reload` during development to load rsynced Clojure code.
