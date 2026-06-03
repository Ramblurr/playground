(use ../deps/testament)
(import ../lib/skia :as skia)

(defn font-dir
  []
  (or (os/getenv "OTTER_FONT_DIR")
      (skia/default-font-dir)))

(defn skia-module
  []
  (require "../lib/skia" :fresh true))

(deftest public-skia-module-renders-basic-gray8-canvas
  (def frame (skia/create 64 64))
  (skia/clear frame "F")
  (skia/draw-rect frame 4 4 20 18 {:paint {:fill-gray 96 :anti-alias? false}})
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
      "public skia API draws paint specs into a gray8 canvas through one module"))

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
                         :pixel-format :rgba32}
               :canvas @{:width 1264
                         :height 1680
                         :pixel-format :rgba32}}
             observed)
      "default canvas dimensions come from the selected platform provider"))

(deftest clipping-transform-and-scoped-restore-constrain-later-draws
  (def frame (skia/create 48 48))
  (skia/clear frame "F")
  (skia/with-clip-rect frame 8 8 8 8
                       (skia/draw-rect frame 0 0 48 48 {:paint "0"}))
  (skia/with-save frame
                  (skia/translate frame 24 0)
                  (skia/scale frame 2 2)
                  (skia/draw-rect frame 1 1 3 3 {:paint {:fill-gray 96 :anti-alias? false}}))
  (skia/draw-rect frame 0 0 4 4 {:paint {:fill-gray 160 :anti-alias? false}})
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
  (skia/clear frame "F")
  (def result
    (protect
      (skia/with-clip-rect frame 0 0 4 4
                           (error "boom"))))
  (skia/draw-rect frame 8 8 4 4 {:paint {:fill-gray 96 :anti-alias? false}})
  (def observed
    @{:body-failed? (not (get result 0))
      :after-error-draw (skia/sample-gray frame 9 9)})
  (is (deep= @{:body-failed? true
               :after-error-draw 96}
             observed)
      "with-clip-rect restores canvas state after errors"))

(deftest lines-paths-polygons-and-triangles-render-through-public-api
  (def frame (skia/create 40 40))
  (skia/clear frame "F")
  (skia/draw-line frame 2 2 20 2 {:paint {:stroke-gray 32 :width 1 :anti-alias? false}})
  (skia/draw-polygon frame @[[8 8] [18 8] [8 18]] {:paint {:fill-gray 96 :anti-alias? false}})
  (skia/draw-path frame @[[22 22] [32 22] [32 32] [22 32]] {:paint {:fill-gray 160 :anti-alias? false}})
  (skia/draw-triangle frame 4 28 14 28 9 20 {:paint "0"})
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

(deftest stroke-and-multiple-paint-specs-render-in-order
  (def frame (skia/create 32 32))
  (skia/clear frame {:fill-gray 128})
  (skia/draw-rect frame 4 4 16 16 {:paint [{:fill "F" :anti-alias? false}
                                           {:stroke "0" :width 1 :anti-alias? false}]})
  (skia/draw-rounded-rect frame 22 4 6 6 2 {:paint {:stroke-gray 0 :width 1 :anti-alias? false}})
  (def observed
    @{:background (skia/sample-gray frame 0 0)
      :filled-center (skia/sample-gray frame 12 12)
      :stroked-edge (skia/sample-gray frame 4 4)
      :rounded-stroke (skia/sample-gray frame 25 4)
      :rounded-center (skia/sample-gray frame 25 7)})
  (is (deep= @{:background 128
               :filled-center 255
               :stroked-edge 0
               :rounded-stroke 0
               :rounded-center 128}
             observed)
      "shape nodes draw multiple paint specs in order and stroke paints do not fill interiors"))

(deftest drawing-primitives-use-paint-options-and-reject-gray-only-api
  (def frame (skia/create 32 32))
  (def module (skia-module))
  (def observed
    @{:raw-black-removed? (nil? (get module 'black))
      :raw-white-removed? (nil? (get module 'white))
      :clear-gray-rejected? (not (get (protect (skia/clear frame {:gray 255})) 0))
      :rect-gray-rejected? (not (get (protect (skia/draw-rect frame 0 0 4 4 {:gray 0})) 0))
      :line-gray-rejected? (not (get (protect (skia/draw-line frame 0 0 4 4 {:gray 0 :stroke-width 1})) 0))
      :clear-color-accepted? (get (protect (skia/clear frame "F")) 0)
      :clear-fill-accepted? (get (protect (skia/clear frame {:fill-gray 255})) 0)
      :clear-stroke-rejected? (not (get (protect (skia/clear frame {:stroke "0" :width 1})) 0))
      :rect-paint-accepted? (get (protect (skia/draw-rect frame 0 0 4 4 {:paint "0"})) 0)
      :line-paint-accepted? (get (protect (skia/draw-line frame 0 0 4 4 {:paint {:stroke "0" :width 1}})) 0)})
  (is (deep= @{:raw-black-removed? true
               :raw-white-removed? true
               :clear-gray-rejected? true
               :rect-gray-rejected? true
               :line-gray-rejected? true
               :clear-color-accepted? true
               :clear-fill-accepted? true
               :clear-stroke-rejected? true
               :rect-paint-accepted? true
               :line-paint-accepted? true}
             observed)
      "drawing primitives accept paint specs and reject gray-only proof-of-concept options"))

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
  (skia/clear frame "F")
  (def line (skia/shape-text frame "Hello" {:font-family "Noto Sans"
                                            :font-size 24
                                            :font-weight 400}))
  (def metrics (skia/text-line-metrics line))
  (def before (skia/stats frame))
  (skia/draw-text-line frame line 10 10 {:paint "0"})
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

(deftest draw-text-line-accepts-paint-options-map
  (def dir (font-dir))
  (def frame (skia/create {:width 320 :height 120 :font-dir dir}))
  (def line (skia/shape-text frame "Hello" {:font-family "Noto Sans"
                                            :font-size 24}))
  (def shorthand-result (protect (skia/draw-text-line frame line 10 10 "0")))
  (def gray-result (protect (skia/draw-text-line frame line 10 10 {:gray 0})))
  (def opts-result (protect (skia/draw-text-line frame line 10 10 {:paint "0"})))
  (def stroke-result (protect (skia/draw-text-line frame line 10 40 {:paint [{:stroke "0" :width 1}
                                                                             {:fill "0"}]})))
  (def observed
    @{:shorthand-rejected? (not (get shorthand-result 0))
      :gray-key-rejected? (not (get gray-result 0))
      :opts-accepted? (get opts-result 0)
      :stroke-sequence-accepted? (get stroke-result 0)})
  (is (deep= @{:shorthand-rejected? true
               :gray-key-rejected? true
               :opts-accepted? true
               :stroke-sequence-accepted? true}
             observed)
      "draw-text-line accepts paint specs and rejects gray-only options"))

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
      :invalid-message-hints-syntax? (not (nil? (string/find "font feature" (string (get invalid 1)))))})
  (is (deep= @{:accepted @[true true true true true]
               :invalid-failed? true
               :invalid-message-hints-syntax? true}
             observed)
      "font feature strings accept Skija examples and reject invalid syntax"))

(deftest load-png-exposes-image-size-and-draw-image-mutates-canvas
  (def image (skia/load-png "test/fixtures/checker.png"))
  (def frame (skia/create 24 24))
  (skia/clear frame "F")
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
  (skia/clear frame "F")
  (skia/draw-image frame image 10 10 {:src {:x 0 :y 0 :w 1 :h 1}
                                      :w 6 :h 6})
  (is (= 0 (skia/sample-gray frame 10 10))
      "cropped black source pixel is drawn at the requested destination")
  (is (= 255 (skia/sample-gray frame 17 17))
      "draw-image does not write outside the destination rectangle"))

(deftest load-png-reports-normalized-rgba32-image-info
  (def image (skia/load-png "test/fixtures/checker.png"))
  (def observed
    @{:info (skia/image-info image)
      :legacy-size @{:width (skia/image-width image)
                     :height (skia/image-height image)}})
  (is (deep= @{:info @{:width 4 :height 4 :pixel-format :rgba32}
               :legacy-size @{:width 4 :height 4}}
             observed)
      "loaded color PNG images report normalized :rgba32 image info"))

(deftest synthetic-gray8-and-gray8a-images-report-format-info
  (def gray (skia/create-image {:width 2 :height 1 :pixel-format :gray8 :pixels @[0 255]}))
  (def gray-alpha (skia/create-image {:width 2 :height 1 :pixel-format :gray8a :pixels @[0 128 255 128]}))
  (def observed
    @{:gray (skia/image-info gray)
      :gray-alpha (skia/image-info gray-alpha)})
  (is (deep= @{:gray @{:width 2 :height 1 :pixel-format :gray8}
               :gray-alpha @{:width 2 :height 1 :pixel-format :gray8a}}
             observed)
      "synthetic grayscale and grayscale-alpha images report their source formats"))

(deftest gray8-image-source-draws-into-gray8-and-rgba32-canvases
  (def image (skia/create-image {:width 2 :height 1 :pixel-format :gray8 :pixels @[0 255]}))
  (def gray (skia/create {:width 2 :height 1 :pixel-format :gray8}))
  (def rgba (skia/create {:width 2 :height 1 :pixel-format :rgba32}))
  (skia/clear gray "80")
  (skia/clear rgba "F00")
  (skia/draw-image gray image 0 0)
  (skia/draw-image rgba image 0 0)
  (def observed
    @{:gray @[(skia/sample-gray gray 0 0)
              (skia/sample-gray gray 1 0)]
      :rgba @[(skia/sample-rgba rgba 0 0)
              (skia/sample-rgba rgba 1 0)]})
  (is (deep= @{:gray @[0 255]
               :rgba @[@{:r 0 :g 0 :b 0 :a 255}
                       @{:r 255 :g 255 :b 255 :a 255}]}
             observed)
      ":gray8 image sources draw into both render canvas formats"))

(deftest gray8a-image-source-alpha-blends-into-gray8-destinations
  (def image (skia/create-image {:width 2 :height 1 :pixel-format :gray8a :pixels @[0 128 255 128]}))
  (def over-white (skia/create {:width 2 :height 1 :pixel-format :gray8}))
  (def over-black (skia/create {:width 2 :height 1 :pixel-format :gray8}))
  (skia/clear over-white "F")
  (skia/clear over-black "0")
  (skia/draw-image over-white image 0 0)
  (skia/draw-image over-black image 0 0)
  (def observed
    @{:over-white @[(skia/sample-gray over-white 0 0)
                    (skia/sample-gray over-white 1 0)]
      :over-black @[(skia/sample-gray over-black 0 0)
                    (skia/sample-gray over-black 1 0)]})
  (is (deep= @{:over-white @[127 255]
               :over-black @[0 128]}
             observed)
      ":gray8a image sources alpha-blend gray over opaque gray8 destinations"))

(deftest gray8a-image-source-alpha-blends-into-rgba32-and-flattens-alpha
  (def image (skia/create-image {:width 2 :height 1 :pixel-format :gray8a :pixels @[0 128 255 128]}))
  (def frame (skia/create {:width 2 :height 1 :pixel-format :rgba32}))
  (skia/clear frame "0")
  (skia/draw-image frame image 0 0)
  (def observed
    @{:black-half-over-black (skia/sample-rgba frame 0 0)
      :white-half-over-black (skia/sample-rgba frame 1 0)})
  (is (deep= @{:black-half-over-black @{:r 0 :g 0 :b 0 :a 255}
               :white-half-over-black @{:r 128 :g 128 :b 128 :a 255}}
             observed)
      ":gray8a image sources alpha-blend into rgba32 destinations and leave output pixels opaque"))

(deftest explicit-gray8-and-rgba32-canvases-report-format-info
  (def gray (skia/create {:width 16 :height 8 :pixel-format :gray8}))
  (def rgba (skia/create {:width 16 :height 8 :pixel-format :rgba32}))
  (def observed
    @{:gray-info (skia/canvas-info gray)
      :gray-format (skia/pixel-format gray)
      :rgba-info (skia/canvas-info rgba)
      :rgba-format (skia/pixel-format rgba)})
  (is (deep= @{:gray-info @{:width 16 :height 8 :pixel-format :gray8}
               :gray-format :gray8
               :rgba-info @{:width 16 :height 8 :pixel-format :rgba32}
               :rgba-format :rgba32}
             observed)
      "explicit :gray8 and :rgba32 canvases expose format-aware public canvas info"))

(deftest rgba32-canvas-preserves-rgb-paint-channels
  (def frame (skia/create {:width 8 :height 8 :pixel-format :rgba32}))
  (skia/clear frame "FFDD22")
  (skia/draw-rect frame 2 2 2 2 {:paint {:fill "0088FF" :anti-alias? false}})
  (def stats (skia/stats frame))
  (def observed
    @{:background (skia/sample-rgba frame 0 0)
      :rect (skia/sample-rgba frame 2 2)
      :format (get stats :pixel-format)})
  (is (deep= @{:background @{:r 255 :g 221 :b 34 :a 255}
               :rect @{:r 0 :g 136 :b 255 :a 255}
               :format :rgba32}
             observed)
      "rgba32 canvases preserve color channels instead of reducing paint to gray"))

(deftest rgb-paint-drawn-into-gray8-uses-deterministic-luminance
  (def frame (skia/create {:width 3 :height 1 :pixel-format :gray8}))
  (skia/clear frame "F")
  (skia/draw-rect frame 0 0 1 1 {:paint {:fill "F00" :anti-alias? false}})
  (skia/draw-rect frame 1 0 1 1 {:paint {:fill "0F0" :anti-alias? false}})
  (skia/draw-rect frame 2 0 1 1 {:paint {:fill "00F" :anti-alias? false}})
  (let [observed @[(skia/sample-gray frame 0 0)
                   (skia/sample-gray frame 1 0)
                   (skia/sample-gray frame 2 0)]]
    (is (deep= @[76 150 29] observed)
        "RGB paints drawn into :gray8 use the documented luminance conversion")))

(deftest unsupported-canvas-pixel-formats-fail-clearly
  (def observed
    @{:rgb565-rejected? (not (get (protect (skia/create {:width 8 :height 8 :pixel-format :rgb565})) 0))
      :gray8a-canvas-rejected? (not (get (protect (skia/create {:width 8 :height 8 :pixel-format :gray8a})) 0))
      :string-format-rejected? (not (get (protect (skia/create {:width 8 :height 8 :pixel-format "gray8"})) 0))})
  (is (deep= @{:rgb565-rejected? true
               :gray8a-canvas-rejected? true
               :string-format-rejected? true}
             observed)
      "only :gray8 and :rgba32 are accepted render canvas formats in this milestone"))

(run-tests!)
