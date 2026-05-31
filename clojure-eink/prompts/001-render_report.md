# Render performance report

Date: 2026-05-31

## Executive summary

The Java2D rendering path is viable for warm e-reader page turns **if the app does not recompute full-page text layout on every interaction**.

The benchmark did **not** prove that arbitrary uncached screens will render quickly. It proved a narrower and useful point:

```text
Java2D drawing + grayscale byte access + FBInk present can be fast enough
when expensive paragraph layout is retained and reused.
```

Best measured warm path on Kobo:

```text
long-lived JVM + cached TextLayout + reused BufferedImage + no-wait/no-flash present
Java2D render:   ~18.5 ms
native present:  ~192.5 ms
total warm draw: ~211 ms plus command/loop overhead
```

A later freshly packaged run showed a slower native-present sample:

```text
Java2D render:  37.8 ms
native present: 619.2 ms
total:          ~657 ms
```

Both are below the sub-1-second warm page-turn target.

## Scope

Repository:

```text
/home/ramblurr/src/github.com/ramblurr/playground/clojure-eink
```

Current rendering path:

```text
Clojure -> Java2D grayscale BufferedImage -> Java FFM -> libclojure_eink.so -> FBInk -> /dev/fb0
```

Kobo deploy directory used for testing:

```text
/mnt/onboard/clojure-eink-demo
```

Primary files involved:

```text
src/clj/ol/project.clj
src/clj/ol/loop.clj
test/clj/ol/project_test.clj
test/clj/ol/loop_test.clj
scripts/package-kobo-dist.sh
STATUS.md
PERF_NOTES.md
```

## Methodology

### Harness note

The CLI flags such as `--renders`, `--render-mode`, and `--reuse-image` are only a benchmark harness. They are not the important result.

The important result is which Java/Java2D methods were called in each path, and what changed when layout/image data was reused.

### Test categories

I tested these rendering categories:

1. Full paragraph layout every render.
2. Cached paragraph layout, then repeated drawing.
3. Simple `drawString` text without `LineBreakMeasurer`.
4. Rectangle-only drawing without text.
5. Reused full-screen grayscale `BufferedImage`.
6. Native FBInk present with and without wait/flash.
7. Long-lived JVM loop with source reload.

## Actual Java and Java2D calls tested

### 1. Full-page text layout path

This is the original realistic page-body path: create a grayscale image, lay out wrapped paragraph text, draw the title and body, then present.

Per render, the code used these Java objects and method calls.

#### Image creation

```clojure
(BufferedImage. width height BufferedImage/TYPE_BYTE_GRAY)
(.createGraphics image)
```

This creates a full-screen grayscale Java2D image. `TYPE_BYTE_GRAY` is important because it usually gives direct access to an 8-bit gray backing byte array later.

#### Graphics setup

```clojure
(.setRenderingHint g RenderingHints/KEY_TEXT_ANTIALIASING
                     RenderingHints/VALUE_TEXT_ANTIALIAS_ON)
(.setRenderingHint g RenderingHints/KEY_ANTIALIASING
                     RenderingHints/VALUE_ANTIALIAS_ON)
```

#### Background fill

```clojure
(.setColor g Color/WHITE)
(.fillRect g 0 0 width height)
```

#### Font creation

```clojure
(Font. "SansSerif" Font/PLAIN font-size)
(Font. "SansSerif" Font/BOLD title-size)
```

#### Paragraph layout setup

```clojure
(java.text.AttributedString. paragraph)
(.addAttribute attributed TextAttribute/FONT body-font)
(.getIterator attributed)
(.getFontRenderContext g)
(LineBreakMeasurer. iterator frc)
```

#### Wrapped line layout

```clojure
(.nextLayout measurer wrap-width)
(.getAscent layout)
(.getDescent layout)
(.getLeading layout)
```

This loop runs until the page is filled or the paragraph ends. It produces Java2D `TextLayout` objects and baseline positions.

#### Drawing title and body

```clojure
(.setColor g Color/BLACK)
(.setFont g title-font)
(.drawString g "Clojure e-ink PoC" margin margin)
(.draw layout g (float x) (float baseline))
```

Each body line is drawn with `TextLayout.draw`.

#### Cleanup

```clojure
(.dispose g)
```

### 2. Cached layout path

The cached-layout path does the full layout once, then reuses the computed `TextLayout` objects and positions.

On cache miss, it runs the expensive path:

```clojure
AttributedString
AttributedCharacterIterator
FontRenderContext
LineBreakMeasurer
.nextLayout
TextLayout ascent/descent/leading
```

The cached value is effectively:

```clojure
[[text-layout x baseline]
 [text-layout x baseline]
 ...]
```

On cache hit, it skips these calls:

```clojure
(java.text.AttributedString. paragraph)
(.addAttribute attributed TextAttribute/FONT body-font)
(.getIterator attributed)
(.getFontRenderContext g)
(LineBreakMeasurer. iterator frc)
(.nextLayout measurer wrap-width)
```

Warm cached renders still do these calls:

```clojure
(.createGraphics image)
(.setRenderingHint ...)
(.setColor g Color/WHITE)
(.fillRect g 0 0 width height)
(.setColor g Color/BLACK)
(.setFont g title-font)
(.drawString g "Clojure e-ink PoC" margin margin)
(.draw layout g x baseline) ; for each cached TextLayout
(.dispose g)
```

This is the central optimization. It converts repeated full paragraph layout into repeated drawing of already-laid-out lines.

### 3. Simple text comparison path

The simple text path avoided `AttributedString`, `LineBreakMeasurer`, and `TextLayout`.

It split text into simple fixed word groups and drew each line with:

```clojure
(.drawString g line x y)
```

Purpose: measure Java2D text drawing without full paragraph layout.

This was not a real layout engine. It was a comparison path to isolate layout cost.

### 4. Rectangle-only comparison path

The rectangle path avoided text entirely and drew simple bands:

```clojure
(.setColor g Color/BLACK)
(.fillRect g x y w h)
(.setColor g Color/LIGHT_GRAY)
(.fillRect g x y w h)
```

Purpose: measure a primitive Java2D drawing baseline.

### 5. Reused BufferedImage path

The first versions allocated a new image each render:

```clojure
(BufferedImage. width height BufferedImage/TYPE_BYTE_GRAY)
```

The image-reuse path keeps an atom containing the previous image:

```clojure
(atom nil)
```

On each render it checks:

```clojure
same width?
same height?
same BufferedImage type == TYPE_BYTE_GRAY?
```

If compatible, it reuses the existing image. If not, it allocates a new one and stores it.

Even when the image is reused, each render still does:

```clojure
(.createGraphics image)
(.fillRect g 0 0 width height)
...
(.dispose g)
```

So this is not caching a finished screen. It is reusing the byte-backed drawing target.

### 6. Image-to-gray8 extraction path

For `BufferedImage/TYPE_BYTE_GRAY`, the code accesses the raster directly:

```clojure
(.getRaster image)
(.getDataBuffer raster)
(.getSampleModel raster)
(.getData ^DataBufferByte data-buffer)
(.getOffset ^DataBufferByte data-buffer)
(.getScanlineStride ^ComponentSampleModel sample-model)
```

If the backing array is already compact and scanline stride equals width, it returns the byte array directly.

Only if the image has offset or stride padding does it compact rows with:

```clojure
(System/arraycopy raw source-offset compact dest-offset width)
```

Warm measurements showed this path was usually about `0.1 ms`, so it is not a bottleneck.

### 7. Java FFM and native present path

Native library setup used Java FFM:

```clojure
(Path/of ...)
(Arena/global)
(SymbolLookup/libraryLookup path arena)
(Linker/nativeLinker)
(FunctionDescriptor/of ...)
(Linker/downcallHandle ...)
```

Native calls are invoked with:

```clojure
(.invokeWithArguments handle (object-array args))
```

For present, the gray bytes are copied into native memory:

```clojure
(Arena/ofConfined)
(.allocate arena byte-count 1)
(MemorySegment/copy data 0 segment ValueLayout/JAVA_BYTE 0 byte-count)
```

Then the native `eink_present_gray8` downcall is invoked with:

```text
segment
width
height
stride
x
y
waveform
flash?
wait?
```

## How caching was implemented

### Layout cache

The layout cache is an atom-backed Clojure map:

```clojure
(atom {})
```

The simplified lookup pattern is:

```clojure
(if-let [entry (find @cache cache-key)]
  (val entry)
  (let [value (compute-layout)]
    (swap! cache assoc cache-key value)
    value))
```

The cache key is currently roughly:

```clojure
[paragraph width height margin body-font-size title-font-size]
```

The cache value is roughly:

```clojure
[[TextLayout x baseline]
 [TextLayout x baseline]
 ...]
```

So the cache stores **laid-out lines**, not rendered pixels.

### What is skipped on cache hit

A layout cache hit skips the expensive paragraph layout sequence:

```text
text -> AttributedString -> iterator -> LineBreakMeasurer -> nextLayout loop
```

It keeps only:

```text
clear image -> draw title -> draw cached TextLayout lines -> present
```

### Image cache

The image cache is an atom that stores one compatible full-screen `BufferedImage`:

```clojure
(atom nil)
```

The simplified logic is:

```clojure
(if cached image has same width/height/type
  cached image
  (let [image (BufferedImage. width height BufferedImage/TYPE_BYTE_GRAY)]
    (reset! image-cache image)
    image))
```

This cache stores the reusable drawing target. It does **not** store a finished UI screen.

### Long-lived loop cache lifetime

`ol.loop` keeps both caches alive across `render` commands in the same JVM:

```text
layout-cache atom
image-cache atom
```

On `reload`, it reloads `src/clj/ol/project.clj` and clears the caches. The JVM, native backend, fonts, and JIT stay warm.

## What “cached” means for a real app

The benchmark does **not** require caching every whole visual state.

It does not mean:

```text
every screen + every menu + every popup + every highlight combination -> cached bitmap
```

It means:

```text
content/model -> layout/display-list cache -> render into reused image -> FBInk
```

For a real reading app:

### Page body

Cache the expensive page body layout:

- line layouts;
- glyph positions;
- word rectangles;
- baseline positions;
- hit-test data.

A page turn should draw an already-laid-out page, not recompute paragraph wrapping.

### Word highlight

A word press should use cached word bounds and draw a cheap overlay:

```clojure
(.setColor g highlight-color)
(.fillRect g word-x word-y word-w word-h)
```

or a rounded rectangle/underline equivalent.

It should not re-layout the page body.

### Dictionary popup

A dictionary popup should lay out only the popup text. That text is small compared with a full page.

Cache while open if needed:

```text
lookup word + popup width + font -> popup layout
```

### Menus and app screens

Menus should either:

- cache their own small layout/display list; or
- draw simple labels and rectangles directly.

They do not require caching every final framebuffer combination.

### Dynamic composition

A realistic frame composition is:

```text
clear/reuse image
-> draw cached page body
-> draw highlight overlay if any
-> draw popup/menu if any
-> present
```

Only changed components need new layout.

## Findings

### Cold JVM startup remains slow

Startup is still expensive. This is acceptable only for a long-lived app process.

### First render remains slow

First full-screen Java2D text render on Kobo is roughly 6.8-7.3 seconds in these tests.

This likely includes first-time font, Java2D, text layout, and JIT effects.

### Repeated uncached page layout is too slow

Default `LineBreakMeasurer` mode, render-only:

```text
render 1/5: 7033.9 ms
render 2/5: 1138.1 ms
render 3/5: 1080.1 ms
render 4/5:  792.3 ms
render 5/5: 1020.3 ms
```

Warm uncached layout often sits around 0.8-1.1 seconds before native present cost.

### Cached text layout is the main win

Cached-layout mode, render-only:

```text
render 1/5: 7004.8 ms
render 2/5:   35.5 ms
render 3/5:   31.9 ms
render 4/5:   39.5 ms
render 5/5:   21.0 ms
```

Caching `TextLayout` results removes the main warm bottleneck.

### Reusing the BufferedImage helps but is secondary

Best measured long-lived loop result with cached layout and reused image:

```text
first render command:  ~6941 ms
second render command: 18.5 ms Java2D render
native present:        192.5 ms
```

A freshly packaged repeat produced:

```text
second render command: 37.8 ms Java2D render
native present:        619.2 ms
```

Image reuse reduces allocation noise, but layout caching is the decisive improvement.

### image->gray8 is not a warm bottleneck

After warmup, `image->gray8` was typically around `0.1 ms` because `TYPE_BYTE_GRAY` exposes a byte-backed raster in the common case.

### Native present is acceptable but variable

Measured native present samples:

```text
no-wait/no-flash: ~192.5 ms, ~213.1 ms, ~220.5 ms, one later sample ~619.2 ms
default wait:     ~792.8 ms
```

The variance should be investigated later, but it does not currently rule out the architecture.

### Reload works

The long-lived loop can reload Clojure source without restarting the JVM.

Measured after `reload`:

```text
first render after reload: ~1323.7 ms
next render:                 ~34.1 ms
```

The JVM, native backend, fonts, and JIT remain warm. The layout and image caches are cleared on reload.

## Recommendations

### 1. Continue with Java2D for the next prototype

Do not abandon Java2D yet. The current measurements show Java2D can meet warm e-reader page-turn targets when layout is retained.

### 2. Build a retained layout/display-list model

Represent screens/pages as cached layout artifacts, not immediate-mode text layout on every frame.

Suggested cache key inputs:

- content identity/version;
- viewport width and height;
- margins;
- font family, size, style;
- line spacing and paragraph style;
- locale/script settings;
- theme/render mode if it affects layout.

Suggested cached values:

- line layouts;
- glyph or word bounds;
- draw commands/display-list entries;
- hit-test data for selection and dictionary lookup.

### 3. Cache page body separately from overlays

Do not cache every visual combination.

Cache stable parts:

- page body layout;
- menu layout;
- popup layout while open.

Draw dynamic parts cheaply:

- word highlight rectangle;
- selection handles;
- cursor/focus state;
- popup background and border.

### 4. Keep reusing the full-screen grayscale image

Keep one or more reusable `BufferedImage/TYPE_BYTE_GRAY` targets. This reduces allocation noise and helps keep warm rendering predictable.

### 5. Pre-layout likely next content in the background

For reading flows, precompute layout for:

- current page;
- next page;
- previous page;
- maybe the next chapter/menu screen if predictable.

This moves unavoidable layout cost away from the page-turn interaction.

### 6. Replace stdin loop with a small control protocol

`ol.loop` proves the long-lived/reloadable JVM path. For a real app or better remote testing, replace stdin with a small socket or request protocol.

Needed operations:

```text
render opts
reload
clear-cache
status
quit
```

### 7. Add representative UI benchmarks

Next benchmarks should model real app interactions:

- turn page with cached next page;
- press word and draw highlight;
- open dictionary popup;
- close popup and restore page;
- open/close menu;
- change font size, forcing layout invalidation;
- render mixed text lengths and styles.

Measure render time, present time, and cache hit/miss behavior for each.

### 8. Investigate native present variance

The no-wait/no-flash present path varied from about `192 ms` to `619 ms`. Determine whether this is waveform behavior, FBInk state, device load, command timing, or measurement noise.

### 9. Defer native FreeType/HarfBuzz until representative cached UI fails

A native text stack may still be useful for quality, shaping, or control. But based on current data, it is not yet required for warm rendering performance.

Only move to native FreeType/HarfBuzz if:

- cached Java2D layout cannot handle representative UI under budget;
- Java2D text quality is unacceptable;
- needed shaping/script support is missing or too slow;
- memory use from Java2D layout caches becomes unacceptable.

## Artifacts produced

Committed checkpoints include:

```text
22064c1 Add render benchmark modes
f28ab6a Keep native screen query for no-present benchmarks
2b310b2 Add render mode benchmarks
03f4e06 Add long-lived render loop
0bec4d4 Reuse layout cache in render loop
0f259c7 Document Kobo render performance
4234d35 Support reusable render image
7703236 Document image reuse benchmark
91d1d15 Add Kobo dist packaging script
```

Important files:

```text
src/clj/ol/project.clj
src/clj/ol/loop.clj
test/clj/ol/project_test.clj
test/clj/ol/loop_test.clj
scripts/package-kobo-dist.sh
STATUS.md
PERF_NOTES.md
prompts/001-render-task.md
prompts/001-render_report.md
```
