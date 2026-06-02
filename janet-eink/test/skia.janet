(use ../deps/testament)
(import ../lib/skia :as skia)

(defn font-dir
  []
  (or (os/getenv "OTTER_FONT_DIR")
      (skia/default-font-dir)))

(deftest public-skia-module-renders-basic-gray8-canvas
  (def frame (skia/create 64 64))
  (skia/clear frame skia/white)
  (skia/draw-rect frame 4 4 20 18 skia/dark-gray)
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
  (is (deep= @{:screen @{:width 1680
                         :height 1264
                         :pixel-format :gray8}
               :canvas @{:width 1680
                         :height 1264
                         :pixel-format :gray8}}
             observed)
      "default canvas dimensions come from the selected platform provider"))

(deftest clipping-transform-and-scoped-restore-constrain-later-draws
  (def frame (skia/create 48 48))
  (skia/clear frame skia/white)
  (skia/with-clip-rect frame 8 8 8 8
    (skia/draw-rect frame 0 0 48 48 skia/black))
  (skia/with-save frame
    (skia/translate frame 24 0)
    (skia/scale frame 2 2)
    (skia/draw-rect frame 1 1 3 3 skia/dark-gray))
  (skia/draw-rect frame 0 0 4 4 160)
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
  (skia/clear frame skia/white)
  (def result
    (protect
      (skia/with-clip-rect frame 0 0 4 4
        (error "boom"))))
  (skia/draw-rect frame 8 8 4 4 skia/dark-gray)
  (def observed
    @{:body-failed? (not (get result 0))
      :after-error-draw (skia/sample-gray frame 9 9)})
  (is (deep= @{:body-failed? true
               :after-error-draw 96}
             observed)
      "with-clip-rect restores canvas state after errors"))

(deftest lines-paths-polygons-and-triangles-render-through-public-api
  (def frame (skia/create 40 40))
  (skia/clear frame skia/white)
  (skia/draw-line frame 2 2 20 2 {:gray 32 :stroke-width 1})
  (skia/draw-polygon frame @[[8 8] [18 8] [8 18]] skia/dark-gray)
  (skia/draw-path frame @[[22 22] [32 22] [32 32] [22 32]] 160)
  (skia/draw-triangle frame 4 28 14 28 9 20 skia/black)
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

(deftest measure-and-draw-single-line-labels-with-noto-families
  (def dir (font-dir))
  (def frame (skia/create {:width 320 :height 120 :font-dir dir}))
  (skia/clear frame skia/white)
  (def sans (skia/measure-text frame "Hello" {:font :sans :size 24}))
  (def serif (skia/measure-text frame "Hello" {:font :serif :size 24}))
  (def before (skia/stats frame))
  (skia/draw-text frame "Hello" 10 10 {:font :sans :size 24 :gray skia/black})
  (skia/draw-text frame "Café — Ω" 10 50 {:font :serif :size 24 :gray skia/dark-gray})
  (def after (skia/stats frame))
  (def observed
    @{:sans-positive? (and (> (get sans :width) 0)
                           (> (get sans :height) 0)
                           (> (get sans :baseline) 0))
      :serif-positive? (and (> (get serif :width) 0)
                            (> (get serif :height) 0)
                            (> (get serif :baseline) 0))
      :draw-mutated? (> (get after :non-white-pixels)
                        (get before :non-white-pixels))})
  (is (deep= @{:sans-positive? true
               :serif-positive? true
               :draw-mutated? true}
             observed)
      "single-line text measurement and drawing work with Noto Sans and Serif"))

(deftest load-png-exposes-image-size-and-draw-image-mutates-canvas
  (def image (skia/load-png "test/fixtures/checker.png"))
  (def frame (skia/create 24 24))
  (skia/clear frame skia/white)
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
  (skia/clear frame skia/white)
  (skia/draw-image frame image 10 10 {:src {:x 0 :y 0 :w 1 :h 1}
                                      :w 6 :h 6})
  (is (= 0 (skia/sample-gray frame 10 10))
      "cropped black source pixel is drawn at the requested destination")
  (is (= 255 (skia/sample-gray frame 17 17))
      "draw-image does not write outside the destination rectangle"))

(run-tests!)
