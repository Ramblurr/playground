(use ../deps/testament)
(import ../lib/skia :as skia)

(defn font-dir
  []
  (or (os/getenv "OTTER_FONT_DIR")
      (skia/default-font-dir)))

(deftest public-skia-module-renders-basic-gray8-canvas
  (def frame (skia/create 64 64))
  (skia/clear frame {:gray skia/white})
  (skia/draw-rect frame 4 4 20 18 {:gray skia/dark-gray})
  (def stats (skia/stats frame))
  (def observed
    @{:background (skia/sample-gray frame 0 0)
      :rect (skia/sample-gray frame 8 8)
      :stats @{:width (get stats :width)
               :height (get stats :height)
               :pixel-format (get stats :pixel-format)
               :min-gray (get stats :min-gray)
               :max-gray (get stats :max-gray)
               :gray-shades (get stats :gray-shades)}})
  (is (deep= @{:background 255
               :rect 96
               :stats @{:width 64
                        :height 64
                        :pixel-format :gray8
                        :min-gray 96
                        :max-gray 255
                        :gray-shades 2}}
             observed)
      "public skia API draws into a gray8 canvas through one module"))

(deftest public-skia-module-uses-platform-screen-size-for-default-canvas
  (def size (skia/screen-size))
  (def frame (skia/create))
  (def stats (skia/stats frame))
  (def observed
    @{:screen @{:width (get size :width)
               :height (get size :height)
               :pixel-format (get size :pixel-format)}
      :canvas @{:width (get stats :width)
               :height (get stats :height)
               :pixel-format (get stats :pixel-format)}})
  (is (deep= @{:screen @{:width 1264
                         :height 1680
                         :pixel-format :gray8}
               :canvas @{:width 1264
                         :height 1680
                         :pixel-format :gray8}}
             observed)
      "default canvas dimensions come from the selected platform provider"))

(deftest clipping-transform-and-scoped-restore-constrain-later-draws
  (def frame (skia/create 48 48))
  (skia/clear frame {:gray skia/white})
  (skia/with-clip-rect frame 8 8 8 8
    (skia/draw-rect frame 0 0 48 48 {:gray skia/black}))
  (skia/with-save frame
    (skia/translate frame 24 0)
    (skia/scale frame 2 2)
    (skia/draw-rect frame 1 1 3 3 {:gray skia/dark-gray}))
  (skia/draw-rect frame 0 0 4 4 {:gray 160})
  (def observed
    @{:clip-inside (skia/sample-gray frame 10 10)
      :clip-outside (skia/sample-gray frame 2 10)
      :translated-scaled (skia/sample-gray frame 27 3)
      :post-restore-origin (skia/sample-gray frame 2 2)
      :post-restore-no-translate (skia/sample-gray frame 26 2)})
  (is (deep= @{:clip-inside 0
               :clip-outside 255
               :translated-scaled 96
               :post-restore-origin 160
               :post-restore-no-translate 96}
             observed)
      "clip, translate, scale, and restore scope affect only scoped draw operations"))

(deftest scoped-clip-restores-even-when-body-errors
  (def frame (skia/create 24 24))
  (skia/clear frame {:gray skia/white})
  (def result
    (protect
      (skia/with-clip-rect frame 0 0 4 4
        (error "boom"))))
  (skia/draw-rect frame 8 8 4 4 {:gray skia/dark-gray})
  (def observed
    @{:body-failed? (not (get result 0))
      :after-error-draw (skia/sample-gray frame 9 9)})
  (is (deep= @{:body-failed? true
               :after-error-draw 96}
             observed)
      "with-clip-rect restores canvas state after errors"))

(deftest lines-paths-polygons-and-triangles-render-through-public-api
  (def frame (skia/create 40 40))
  (skia/clear frame {:gray skia/white})
  (skia/draw-line frame 2 2 20 2 {:gray 32 :stroke-width 1})
  (skia/draw-polygon frame @[[8 8] [18 8] [8 18]] {:gray skia/dark-gray})
  (skia/draw-path frame @[[22 22] [32 22] [32 32] [22 32]] {:gray 160})
  (skia/draw-triangle frame 4 28 14 28 9 20 {:gray skia/black})
  (def observed
    @{:line (skia/sample-gray frame 10 2)
      :polygon (skia/sample-gray frame 10 10)
      :path (skia/sample-gray frame 26 26)
      :triangle (skia/sample-gray frame 9 25)
      :background (skia/sample-gray frame 35 35)})
  (is (deep= @{:line 32
               :polygon 96
               :path 160
               :triangle 0
               :background 255}
             observed)
      "line, polygon, path, and triangle drawing mutate expected gray8 pixels"))

(deftest drawing-primitives-accept-only-canonical-options-maps
  (def frame (skia/create 32 32))
  (def observed
    @{:clear-shorthand-rejected? (not (get (protect (skia/clear frame skia/white)) 0))
      :rect-shorthand-rejected? (not (get (protect (skia/draw-rect frame 0 0 4 4 skia/black)) 0))
      :line-shorthand-rejected? (not (get (protect (skia/draw-line frame 0 0 4 4 skia/black)) 0))
      :clear-opts-accepted? (get (protect (skia/clear frame {:gray skia/white})) 0)
      :rect-opts-accepted? (get (protect (skia/draw-rect frame 0 0 4 4 {:gray skia/black})) 0)
      :line-opts-accepted? (get (protect (skia/draw-line frame 0 0 4 4 {:gray skia/black :stroke-width 1})) 0)})
  (is (deep= @{:clear-shorthand-rejected? true
               :rect-shorthand-rejected? true
               :line-shorthand-rejected? true
               :clear-opts-accepted? true
               :rect-opts-accepted? true
               :line-opts-accepted? true}
             observed)
      "drawing primitives accept one canonical options-map call shape"))

(deftest deterministic-noto-font-dir-is-available
  (def dir (font-dir))
  (def observed
    @{:has-dir? (not (nil? dir))
      :sans? (if dir (= :file (os/stat (string dir "/NotoSans.ttf") :mode)) false)
      :serif? (if dir (= :file (os/stat (string dir "/NotoSerif.ttf") :mode)) false)})
  (is (deep= @{:has-dir? true
               :sans? true
               :serif? true}
             observed)
      "tests use deterministic Nix-sourced Noto Sans and Noto Serif files"))

(deftest shaped-text-lines-measure-and-draw-with-cap-height-metrics
  (def dir (font-dir))
  (def frame (skia/create {:width 320 :height 120 :font-dir dir}))
  (skia/clear frame {:gray skia/white})
  (def line (skia/shape-text frame "Hello" {:font-family "Noto Sans"
                                        :font-size 24
                                        :font-weight 400}))
  (def metrics (skia/text-line-metrics line))
  (def before (skia/stats frame))
  (skia/draw-text-line frame line 10 10 {:gray skia/black})
  (def after (skia/stats frame))
  (def observed
    @{:metrics-positive? (and (> (get metrics :width) 0)
                              (> (get metrics :height) 0))
      :no-baseline-diagnostics? (and (nil? (get metrics :ascent nil))
                                     (nil? (get metrics :descent nil))
                                     (nil? (get metrics :baseline nil)))
      :draw-mutated? (> (get after :non-white-pixels)
                        (get before :non-white-pixels))})
  (is (deep= @{:metrics-positive? true
               :no-baseline-diagnostics? true
               :draw-mutated? true}
             observed)
      "shaped text lines expose cap-height metrics and draw into a gray8 canvas"))

(deftest draw-text-line-accepts-one-canonical-options-map
  (def dir (font-dir))
  (def frame (skia/create {:width 320 :height 120 :font-dir dir}))
  (def line (skia/shape-text frame "Hello" {:font-family "Noto Sans"
                                        :font-size 24}))
  (def shorthand-result (protect (skia/draw-text-line frame line 10 10 skia/black)))
  (def opts-result (protect (skia/draw-text-line frame line 10 10 {:gray skia/black})))
  (def old-paint-result (protect (skia/draw-text-line frame line 10 10 {:paint skia/black})))
  (def observed
    @{:shorthand-rejected? (not (get shorthand-result 0))
      :old-paint-key-rejected? (not (get old-paint-result 0))
      :opts-accepted? (get opts-result 0)})
  (is (deep= @{:shorthand-rejected? true
               :old-paint-key-rejected? true
               :opts-accepted? true}
             observed)
      "draw-text-line has one canonical options-map call shape"))

(deftest font-feature-strings-follow-skija-syntax
  (def dir (font-dir))
  (def frame (skia/create {:width 320 :height 120 :font-dir dir}))
  (def accepted @[])
  (each feature ["tnum" "+cv09" "-dlig" "wdth=100" "tnum[0:3]"]
    (array/push accepted
                (get (protect (skia/shape-text frame "12345" {:font-family "Noto Sans"
                                                               :font-size 24
                                                               :font-features [feature]}))
                     0)))
  (def invalid
    (protect (skia/shape-text frame "12345" {:font-family "Noto Sans"
                                             :font-size 24
                                             :font-features ["bad"]})))
  (def observed
    @{:accepted accepted
      :invalid-failed? (not (get invalid 0))
      :invalid-message-hints-syntax? (not (nil? (string/find "font feature" (string (get invalid 1)))))} )
  (is (deep= @{:accepted @[true true true true true]
               :invalid-failed? true
               :invalid-message-hints-syntax? true}
             observed)
      "font feature strings accept Skija examples and reject invalid syntax"))

(deftest load-png-exposes-image-size-and-draw-image-mutates-canvas
  (def image (skia/load-png "test/fixtures/checker.png"))
  (def frame (skia/create 24 24))
  (skia/clear frame {:gray skia/white})
  (skia/draw-image frame image 4 4)
  (def stats (skia/stats frame))
  (def observed
    @{:width (skia/image-width image)
      :height (skia/image-height image)
      :drawn-black (skia/sample-gray frame 4 4)
      :background (skia/sample-gray frame 0 0)
      :mutated? (> (get stats :non-white-pixels) 0)})
  (is (deep= @{:width 4
               :height 4
               :drawn-black 0
               :background 255
               :mutated? true}
             observed)
      "load-png returns an image handle and draw-image draws it into the gray8 canvas"))

(deftest draw-image-supports-crop-and-destination-rect
  (def image (skia/load-png "test/fixtures/checker.png"))
  (def frame (skia/create 24 24))
  (skia/clear frame {:gray skia/white})
  (skia/draw-image frame image 10 10 {:src {:x 0 :y 0 :w 1 :h 1}
                                      :w 6 :h 6})
  (is (= 0 (skia/sample-gray frame 10 10))
      "cropped black source pixel is drawn at the requested destination")
  (is (= 255 (skia/sample-gray frame 17 17))
      "draw-image does not write outside the destination rectangle"))

(run-tests!)
