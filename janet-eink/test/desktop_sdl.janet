(use ../deps/testament)
(import ../lib/skia :as skia)
(import ../lib/platform/desktop :as desktop)

(deftest public-skia-drawing-primitives-render-to-desktop-gray8-canvas
  (def frame (skia/create 64 64))
  (skia/clear frame {:gray skia/white})
  (skia/draw-rect frame 4 4 20 18 {:gray 96})
  (skia/draw-triangle frame 10 50 30 28 50 50 {:gray 32})
  (skia/draw-circle frame 48 16 8 {:gray 160})
  (def stats (skia/stats frame))
  (def observed
    @{:background (skia/sample-gray frame 0 0)
      :rect (skia/sample-gray frame 8 8)
      :triangle (skia/sample-gray frame 30 40)
      :circle (skia/sample-gray frame 48 16)
      :pixel-format (get stats :pixel-format)
      :gray-shades (get stats :gray-shades)})
  (is (deep= @{:background 255
               :rect 96
               :triangle 32
               :circle 160
               :pixel-format :gray8
               :gray-shades 4}
             observed)
      "public skia API renders primitives through the desktop native module"))


(deftest desktop-sdl-centers-a-half-scale-portrait-kobo-canvas-in-any-render-output
  (def large (desktop/fixed-viewport 1000 1000))
  (def small (desktop/fixed-viewport 500 400))
  (is (deep= @{:x 184
               :y 80
               :width 632
               :height 840}
             large)
      "larger compositor windows center the half-scale portrait Kobo canvas")
  (is (deep= @{:x -66
               :y -220
               :width 632
               :height 840}
             small)
      "smaller compositor windows clip the half-scale portrait Kobo canvas"))

(run-tests!)
