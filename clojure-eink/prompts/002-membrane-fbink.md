# Membrane FBInk backend PoC

This document is the north star for the next task: build a minimal Membrane backend that renders to the existing Java2D grayscale image + native FBInk path on Kobo.

## Step 0 checkpoint

Before this task, the current project state was checkpointed in git:

```text
7ef593f Checkpoint Kobo rendering PoC
```

That commit intentionally included current project files such as `AGENTS.md`, `screenshot.sh`, `src/native/eink_native.c`, flake/build/dev changes, and the 001 prompt/report docs. It intentionally did not include `.pi/`.

## Goal

Build a basic proof of concept Membrane UI backend for e-ink devices:

```text
Membrane UI value -> Java2D grayscale BufferedImage -> Java FFM -> libclojure_eink.so -> FBInk -> /dev/fb0
```

Input handling is out of scope for this pass. Mouse, keyboard, scroll, clipboard, and windowing should be no-ops or absent.

The first review checkpoint is a basic visible Membrane render on Kobo, for example:

- simple shapes;
- a label;
- a button-like rounded rectangle with text.

Prove it works on Kobo using the existing package/rsync workflow and `screenshot.sh`.

## Local reference source

Membrane checkout:

```text
/home/ramblurr/src/github.com/phronmophobic/membrane
```

Important upstream files inspected:

```text
README.md
docs/tutorial.md
src/membrane/ui.cljc
src/membrane/toolkit.cljc
src/membrane/java2d.clj
src/membrane/component.cljc
src/membrane/basic_components.cljc
src-java/com/phronemophobic/membrane/Skia.java
```

## Research notes

### Membrane architecture

From upstream `README.md`, Membrane separates:

1. `membrane.component` — optional UI framework/state management;
2. `membrane.ui` — platform-agnostic graphics and event model;
3. backend namespaces such as `membrane.java2d` — concrete drawing implementations.

For a platform backend, Membrane needs:

- drawing implementations for primitives;
- an event loop that forwards events and repaints.

For this task, the event loop/input side is intentionally a no-op. We only need rendering.

### Upstream Java2D backend shape

`src/membrane/java2d.clj` defines:

```clojure
(defprotocol IDraw
  :extend-via-metadata true
  (draw [this]))

(ui/add-default-draw-impls! IDraw #'draw)
```

Then it extends `IDraw` for Membrane primitives, including:

- `membrane.ui.Label`;
- `membrane.ui.Translate`;
- `membrane.ui.Image`;
- `membrane.ui.Path`;
- `membrane.ui.RoundedRectangle`;
- `membrane.ui.WithColor`;
- `membrane.ui.Scale`;
- `membrane.ui.ScissorView`;
- `membrane.ui.ScrollView`.

It renders into a dynamic Java2D graphics context:

```clojure
(def ^:dynamic *g* nil)
```

and uses helper macros to save/restore state:

```clojure
push-paint
push-stroke
push-transform
push-color
push-font
```

### Upstream Java2D text methods

`membrane.java2d` does **not** use `LineBreakMeasurer` for basic labels. It uses simpler Java2D font APIs:

For bounds:

```clojure
(.getLineMetrics ^Font font text frc)
(.getStringBounds ^Font font line frc)
```

For drawing:

```clojure
(.setFont ^Graphics2D *g* font)
(.drawString ^Graphics2D *g* ^String line 0 0)
```

This aligns with the previous performance finding: avoid `LineBreakMeasurer` in hot UI rendering.

### Membrane `ui/button`

`membrane.ui/button` is already a drawable primitive in `membrane.ui`, not only a component. It builds a button-like visual from:

- `rounded-rectangle`;
- `with-style`;
- `with-color`;
- `translate`;
- `label`.

This is suitable for the first render proof without implementing input.

### Vendoring implications

The minimum useful source files for rendering are likely:

```text
src/membrane/ui.cljc
src/membrane/toolkit.cljc
```

A backend can then be written as a new local file:

```text
src/clj/membrane/fbink.clj
```

Options for `component.cljc`:

- Do not vendor it for the first rendering-only proof if `membrane.ui/button` is enough.
- Vendor it later if the proof needs `defui`, `make-app`, effects, or stateful components.
- If vendored, it retains namespace `membrane.component`, but it brings external dependency needs: `com.rpl/specter`, `org.clojure/core.cache`, and wrapped cache support.

Options for `java2d.clj`:

- Do not use it directly because it includes Swing/window/input code that is irrelevant on Kobo.
- Use it as a reference for primitive drawing methods.
- Copy only the relevant rendering portions into `membrane.fbink`, adapted to grayscale image + FBInk present.

No `src-java` files appear necessary for the basic Java2D/FBInk backend. `src-java/com/phronemophobic/membrane/Skia.java` is for the Skia backend, not this path.

## Performance constraints from task 001

Previous benchmarks showed:

- `LineBreakMeasurer.nextLayout` is too slow for dynamic UI hot paths.
- Basic Java2D drawing and cached `TextLayout.draw` are fast enough.
- `BufferedImage/TYPE_BYTE_GRAY` gives fast `image->gray8` access.
- Reusing a compatible `BufferedImage` improves warm predictability.

Therefore, the Membrane FBInk backend should:

- use `Font.getStringBounds`, `Font.getLineMetrics`, `Font.createGlyphVector`, `Graphics2D.drawString`, and shape drawing for labels/buttons;
- avoid `LineBreakMeasurer` in the backend;
- only use `TextLayout` deliberately for cases that need advanced shaping, and cache any such layouts by text/font/render settings;
- reuse a full-screen `BufferedImage/TYPE_BYTE_GRAY` across frames;
- keep native FBInk initialized in a long-lived process.

## Proposed design

### Vendored namespaces

Copy upstream files into this repo with the same namespaces:

```text
src/clj/membrane/ui.cljc
src/clj/membrane/toolkit.cljc
```

Possibly later:

```text
src/clj/membrane/component.cljc
```

Do not vendor the entire Membrane tree.

### Backend namespace

Create:

```text
src/clj/membrane/fbink.clj
```

The backend should expose a small API similar to:

```clojure
(render-image! context elem opts)  ;; draw Membrane elem into reusable image
(present! context elem opts)       ;; render + FBInk present
(run-once! elem opts)              ;; one-shot proof
(run-loop! view-fn opts)           ;; optional later, no input for now
```

### Rendering context

Context should hold:

```clojure
{:native native-handles
 :native-lib path
 :width screen-width
 :height screen-height
 :image-cache (atom nil)
 :image-cache-key (atom nil)
 :font-cache (atom {})
 :image-resource-cache (atom {})}
```

The `BufferedImage` reuse logic can follow `ol.project`:

```text
if cached image has same width/height/type, reuse it;
otherwise allocate BufferedImage/TYPE_BYTE_GRAY.
```

### Primitive drawing implementation

Use an `IDraw` protocol like upstream Java2D:

```clojure
(defprotocol IDraw
  :extend-via-metadata true
  (draw [this]))
```

Call:

```clojure
(ui/add-default-draw-impls! IDraw #'draw)
```

Implement at least:

- vectors/sequences through default draw impls;
- `membrane.ui.Label`;
- `membrane.ui.Translate`;
- `membrane.ui.WithColor`;
- `membrane.ui.WithStyle`;
- `membrane.ui.WithStrokeWidth`;
- `membrane.ui.Rectangle`;
- `membrane.ui.RoundedRectangle`;
- `membrane.ui.Path`;
- `membrane.ui.Scale` if needed by button/layout;
- `membrane.ui.Spacer` no-op if default draw impl does not cover it.

### Text rendering policy

For `membrane.ui.Label`, use simple per-line drawing:

```clojure
(clojure.string/split text #"\n" -1)
(.getLineMetrics font text frc)
(.getStringBounds font line frc)
(.drawString g line 0 y)
```

Do not use `LineBreakMeasurer` for labels/buttons.

Cache Java `Font` objects by Membrane font record:

```clojure
{:name name :size size :weight weight :slant slant}
```

Optional later: cache string bounds or glyph vectors if labels are repeatedly measured and this becomes visible in timings.

### First demo UI

Create a demo namespace such as:

```text
src/clj/ol/membrane_demo.clj
```

Example UI:

```clojure
(ui/vertical-layout
  (ui/with-color [0 0 0]
    (ui/label "Membrane on FBInk" (ui/font nil 42)))
  (ui/spacer 0 24)
  (ui/button "Dictionary"))
```

Or a manually composed button if upstream `ui/button` pulls in too much:

```clojure
[(ui/with-color [0.85 0.85 0.85]
   (ui/rounded-rectangle 360 96 8))
 (ui/translate 32 56
   (ui/label "Dictionary" (ui/font nil 36)))]
```

### Packaging

Update `scripts/package-kobo-dist.sh` to include vendored Membrane source and demo namespace automatically via `src/clj` copy.

Add a runner such as:

```text
target/dist/run-membrane-demo.sh
```

or reuse `run-demo.sh` with a new mode if cleaner.

### Kobo proof workflow

1. Build/package:

   ```sh
   scripts/package-kobo-dist.sh
   ```

2. Rsync:

   ```sh
   rsync -rtv --delete --no-owner --no-group --no-perms target/dist/ \
     root@kobo-lan:/mnt/onboard/clojure-eink-demo/
   ```

3. Run on Kobo:

   ```sh
   ssh root@kobo-lan
   cd /mnt/onboard/clojure-eink-demo
   ./run-membrane-demo.sh --no-wait --no-flash
   ```

4. Capture screenshot from workstation:

   ```sh
   bash screenshot.sh
   ```

5. Inspect screenshot enough to confirm visible shapes/text/button.

## Acceptance criteria for first review checkpoint

Stop and call for review when all are true:

- source vendoring is minimal and documented;
- backend can render a Membrane UI value into `BufferedImage/TYPE_BYTE_GRAY`;
- backend can present that image through existing native FBInk functions;
- no input handling is implemented beyond no-op/absence;
- local tests or smoke commands pass;
- Kobo run succeeds;
- screenshot shows the Membrane demo UI, at minimum shapes plus label or button.

## Open questions

- Should `membrane.component` be vendored immediately, or wait until the first pure `membrane.ui` render proof works?
- Should the backend namespace be `membrane.fbink`, `membrane.eink`, or `ol.membrane.fbink`? The current plan uses `membrane.fbink` to mirror `membrane.java2d`.
- Should text bounds be cached from the start, or only if label measurement is slow on Kobo?
- Should the demo use `ui/button` directly or a manually composed button to reduce dependencies during first proof?

## Initial implementation plan

1. Vendor `membrane.ui` and `membrane.toolkit` only.
2. Create `membrane.fbink` from the drawing portions of `membrane.java2d`, excluding Swing/input/window code.
3. Add a tiny demo namespace that renders label + rounded rectangle/button.
4. Render locally to PNG first for quick smoke testing.
5. Wire FBInk presentation using existing `ol.project` native functions.
6. Package and run on Kobo.
7. Capture screenshot and request review.
