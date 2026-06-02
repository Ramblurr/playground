(use ../deps/testament)
(import ../lib/desktop :as desktop)

(deftest desktop-drawing-primitives-render-to-gray8-canvas
  (def frame (desktop/create 64 64))
  (desktop/clear frame 255)
  (desktop/draw-rect frame 4 4 20 18 96)
  (desktop/draw-triangle frame 10 50 30 28 50 50 32)
  (desktop/draw-circle frame 48 16 8 160)
  (is (= 255 (desktop/sample-gray frame 0 0)) "clear fills untouched pixels with white")
  (is (= 96 (desktop/sample-gray frame 8 8)) "draw-rect fills the requested gray")
  (is (= 32 (desktop/sample-gray frame 30 40)) "draw-triangle fills the requested gray")
  (is (= 160 (desktop/sample-gray frame 48 16)) "draw-circle fills the requested gray")
  (def stats (desktop/stats frame))
  (is (= :gray8 (get stats :pixel-format)) "drawing backend stores a gray8 Skia canvas")
  (is (= 4 (get stats :gray-shades)) "stats count clear plus the three drawn shades"))

(deftest desktop-demo-scene-renders-kobo-sized-gray-shape-screen
  (def stats (desktop/render-demo-self-test))
  (is (= 1680 (get stats :width)) "demo scene uses the fixed Kobo canvas width")
  (is (= 1264 (get stats :height)) "demo scene uses the fixed Kobo canvas height")
  (is (= :gray8 (get stats :pixel-format)) "demo scene renders through the gray8 Skia layer")
  (is (= 0 (get stats :min-gray)) "demo scene includes black ink")
  (is (= 255 (get stats :max-gray)) "demo scene keeps a white background")
  (is (>= (get stats :gray-shades) 8) "demo scene contains many e-ink gray shades")
  (is (> (get stats :non-white-pixels) 200000) "demo scene draws substantial non-white geometry")
  (is (> (get stats :checksum) 0) "demo scene has stable non-empty pixel data"))

(deftest desktop-sdl-centers-a-fixed-kobo-canvas-in-any-render-output
  (def large (desktop/fixed-viewport 2000 1400))
  (def small (desktop/fixed-viewport 1000 800))
  (is (deep= @{:x 160
               :y 68
               :width 1680
               :height 1264}
             large)
      "larger compositor windows center the fixed Kobo canvas without scaling")
  (is (deep= @{:x -340
               :y -232
               :width 1680
               :height 1264}
             small)
      "smaller compositor windows clip a fixed Kobo canvas instead of scaling it"))

(run-tests!)
