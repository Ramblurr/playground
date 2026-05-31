# Membrane run loop and gray8 damage tracking

This document is the task 003 handoff and progress log for turning the Membrane/FBInk proof into a long-lived runnable backend with basic pixel damage tracking.

## Working directory

```text
/home/ramblurr/src/github.com/ramblurr/playground/clojure-eink
```

## Current baseline

The Membrane render proof currently has this shape:

```text
src/clj/membrane/                  vendored upstream-only source
  ui.cljc
  toolkit.cljc

src/clj/ol/membrane/eink_backend.clj  actual backend implementation
src/clj/ol/membrane_demo.clj          demo / PoC UI and CLI entrypoint
```

The backend path is:

```text
Membrane UI value
 -> Java2D BufferedImage/TYPE_BYTE_GRAY
 -> ol.project/image->gray8
 -> ol.project/present-gray8!
 -> native FBInk
```

Important rule from review: keep strict separation between actual backend code and demo/test/PoC code. `src/clj/membrane/` must remain unmodified vendored upstream source. Generic backend code belongs under `ol.membrane.*`; demo UI belongs in `ol.membrane-demo` or other `ol.*` demo namespaces.

## Task goal

Build a fuller Membrane e-ink backend runner:

1. Keep native FBInk, image buffers, font caches, and previous framebuffer bytes alive across renders.
2. Provide a reusable backend context/lifecycle API.
3. Provide a long-lived run loop suitable for iterative development and warm render benchmarking.
4. Add gray8 pixel damage tracking after final framebuffer-format conversion.
5. Use damage information to skip unchanged presents and present only a bounding dirty rectangle for changed pixels.

## Research notes

### Membrane Java2D runner

Upstream reference:

```text
/home/ramblurr/src/github.com/phronmophobic/membrane/src/membrane/java2d.clj
```

Relevant findings:

- `draw-to-image` renders an element into an image, fills white, sets black, and calls `draw`.
- `run` creates a window/panel, stores `:ui` and `:render`, and repaints by recomputing the view function.
- `run` returns a map containing a repaint function (`::repaint`) and frame handle.
- `run-sync` blocks until the window closes.
- Java2D runner forwards input events to `membrane.ui` and repaints.

For Kobo/e-ink in this pass:

- no Swing/window/input;
- no event forwarding yet;
- a runner can be stdin/REPL-command driven;
- `view-fn` should be called for each render, as in Membrane toolkit semantics;
- the backend should expose enough lifecycle hooks for a future real input loop.

### Membrane toolkit protocols

Vendored `membrane.toolkit` defines:

```clojure
IToolkitRun/run
IToolkitRunSync/run-sync
IToolkitFontMetrics/font-metrics
IToolkitFontAdvanceX/font-advance-x
IToolkitFontLineHeight/font-line-height
IToolkitSaveImage/save-image
```

A later polished backend can expose a `toolkit` reify object. The immediate value is the backend context and run loop; toolkit conformance can follow once the runner API stabilizes.

### Damage tracking hook

The correct damage hook is after conversion to the exact gray8 bytes to be sent to the device:

```clojure
(let [image (render-to-image! elem opts)
      gray  (project/image->gray8 image)]
  ...diff gray...)
```

Do not diff Membrane trees and do not diff the pre-conversion `BufferedImage` as an abstract image. Diff the final `gray` map:

```clojure
{:width w
 :height h
 :stride stride
 :data byte-array}
```

Do not keep `(:data gray)` itself as previous state when reusing `BufferedImage`; it may be the image backing store and mutate on the next render. Keep a separate copied byte-array snapshot.

Initial algorithm:

```text
render full image
convert to gray8
compare current gray8 bytes with previous copied gray8 bytes
compute one bounding changed rect
if nothing changed: skip present
if dirty area is large or previous is absent: present full gray8
else crop changed rect from current gray8 and present at x/y
copy current gray8 into previous buffer after successful changed/full present
```

Start with a single bounding rectangle. Later improvements can tile diff (32x32 or 64x64), merge neighboring tiles, and choose waveforms based on dirty region and update count.

## Proposed backend API

In `ol.membrane.eink-backend`:

```clojure
(open-context! opts)
(close-context! context)
(render-frame! context elem opts)
(diff-gray8 previous current)
(crop-gray8 current rect)
(snapshot-gray8 current)
(present-frame! context elem opts)
(run-loop! view-fn opts)
(run view-fn opts)
(run-sync view-fn opts)
```

Suggested context shape:

```clojure
{:native native-handles-or-nil
 :native-lib path-or-nil
 :width width
 :height height
 :image-cache (atom nil)
 :font-cache (atom {})
 :previous-gray (atom nil)
 :render-count (atom 0)
 :partial-count (atom 0)}
```

`render-frame!` should return timing data for at least:

- view construction;
- render to image;
- image->gray8;
- damage diff;
- crop;
- native present.

## Damage policy v1

Options:

```clojure
{:damage? true
 :damage-full-threshold 0.35
 :force-full? false
 :full-refresh-every nil}
```

Rules:

- no previous gray8 -> full present;
- no changed pixels -> skip present;
- dirty rectangle area / screen area >= threshold -> full present;
- otherwise crop and present dirty rectangle at `:x`/`:y`;
- keep a copied current gray8 snapshot after present;
- if many partial presents happened, later force a full refresh to reduce ghosting.

## Current implementation assessment

The current damage implementation is a good v1/proof implementation, not a finished damage system. It is correct in the most important architectural way: it diffs the final `gray8` bytes after `project/image->gray8`, keeps an independent previous snapshot, detects unchanged frames, and can crop/present one bounding dirty rectangle.

Strengths:

- compares the final device-bound bytes, not the Membrane tree;
- avoids the mutable backing-store bug by copying previous bytes;
- naturally handles both old pixels disappearing and new pixels appearing;
- keeps the algorithm simple enough to test and reason about;
- is proven on Kobo for the basic unchanged-frame case: first render full, second identical render skip.

Known gaps before calling this complete:

- print or capture timing breakdowns for diff, crop, and present on Kobo;
- benchmark the byte-by-byte Clojure diff cost on full-screen buffers;
- make `:force-full?` skip diff and present full immediately;
- add full-refresh cadence and ghosting policy;
- add tile-based damage for scattered changes;
- tighten reload behavior for real development loops;
- add tests for threshold/full-present policy and stride edge cases.

Next decision point: benchmark diff cost on Kobo. If full-screen Clojure byte scanning is cheap enough, keep it. If it is visible, optimize the loop or move diff/crop lower-level.

## CLI / run loop behavior

A demo runner can live in `ol.membrane-demo` and call backend functions. It should support commands similar to `ol.loop`:

```text
render [options]   render/present without restarting JVM
reload             load the demo/backend source files and clear caches if needed
help               print commands
quit               close native backend and exit
```

The runner must keep the JVM, native FBInk, image cache, font cache, and previous gray8 snapshot alive across render commands.

## Verification plan

Local:

```sh
bb test
clojure -M -m ol.membrane-demo --no-present --width 320 --height 240 --png target/membrane-demo.png
scripts/package-kobo-dist.sh
```

Kobo:

```sh
rsync -rtv --delete --no-owner --no-group --no-perms target/dist/ \
  root@kobo-lan:/mnt/onboard/clojure-eink-demo/

ssh root@kobo-lan
cd /mnt/onboard/clojure-eink-demo
./run-membrane-demo.sh --no-wait --no-flash
# later: ./run-membrane-loop.sh --no-wait --no-flash
```

Screenshot proof when the displayed UI changes materially:

```sh
bash screenshot.sh
```

## Initial implementation slices

1. Add pure gray8 helpers and tests:
   - copied snapshot;
   - bounding changed rect;
   - crop dirty rect;
   - unchanged detection.
2. Add backend context lifecycle and render-frame helper using image/font caches.
3. Add damage-aware present function using the final gray8 bytes.
4. Add a long-lived Membrane demo loop that uses backend context and damage-aware presents.
5. Package a loop runner script and test on Kobo.
6. Record timings and update this progress log.

## Progress Log

- 2026-05-31 14:08 CEST — Created task 003 planning document. Researched upstream `membrane.java2d/run`, `run-sync`, `draw-to-image`, and vendored `membrane.toolkit` protocols. Captured the design decision to diff after `project/image->gray8`, keep copied previous gray8 bytes, and start with one bounding dirty rectangle before tile-based damage tracking.
- 2026-05-31 14:12 CEST — Started implementation with TDD for pure gray8 damage helpers in `ol.membrane.eink-backend`. Added RED tests for copied snapshots, unchanged detection, bounding dirty rectangle, and compact crop buffers. Implemented `snapshot-gray8`, `diff-gray8`, and `crop-gray8`; verified GREEN with `bb test --focus ol.membrane.eink-backend-test`: `4 tests, 10 assertions, 0 failures`.
- 2026-05-31 14:17 CEST — Added damage-aware present and first runner APIs. TDD added tests for full first present, unchanged skip, partial crop present, context image/font cache reuse, and `render-view!` container-info behavior. Implemented `open-context!`, `close-context!`, `render-frame!`, `present-gray8-with-damage!`, `present-frame!`, `render-view!`, and a stdin `run-loop!` with `render`, `reload`, `help`, and `quit`. Refactored `ol.membrane-demo` one-shot path to use backend context/render functions and added `--loop` mode. Added `run-membrane-loop.sh` packaging. Verified `bb test`: `18 tests, 74 assertions, 0 failures`; local PNG smoke; local no-present loop smoke; and packaged jar containing `ol/membrane/eink_backend.clj`.
- 2026-05-31 14:21 CEST — Deployed packaged task 003 state to Kobo with safe rsync flags. Ran `printf 'render\nrender\nquit\n' | ./run-membrane-loop.sh --no-wait --no-flash` on device. The long-lived loop started, first render presented a full dirty rect `{:x 0, :y 0, :width 1264, :height 1680}`, and the second identical render reported `mode skip dirty none`, proving previous gray8 snapshot comparison skipped native present for unchanged output.
- 2026-05-31 14:25 CEST — Added implementation assessment notes after review. The current damage tracker is documented as a correct v1/proof: it diffs final gray8 bytes, copies previous state, handles unchanged frames and bounding-rect crops, and is proven on Kobo for skip. The doc now also records the known gaps: diff/crop timing, full-screen diff benchmark, `:force-full?` short-circuit, ghosting/full-refresh policy, tile damage, reload tightening, and extra policy/stride tests.
