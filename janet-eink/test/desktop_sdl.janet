(use ../deps/testament)
(import ../lib/skia :as skia)
(import ../lib/platform/desktop :as desktop)
(import ../lib/demo/shapes :as shapes)

(deftest public-skia-drawing-primitives-render-to-desktop-gray8-canvas
  (def frame (skia/create 64 64))
  (skia/clear frame skia/white)
  (skia/draw-rect frame 4 4 20 18 96)
  (skia/draw-triangle frame 10 50 30 28 50 50 32)
  (skia/draw-circle frame 48 16 8 160)
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

(deftest janet-demo-scene-renders-portrait-kobo-sized-gray-shape-screen
  (def frame (skia/create 1264 1680))
  (shapes/draw frame)
  (def stats (skia/stats frame))
  (def observed
    @{:width (get stats :width)
      :height (get stats :height)
      :pixel-format (get stats :pixel-format)
      :has-black? (= 0 (get stats :min-gray))
      :has-white? (= 255 (get stats :max-gray))
      :many-shades? (>= (get stats :gray-shades) 8)
      :substantial-ink? (> (get stats :non-white-pixels) 200000)
      :non-empty? (> (get stats :checksum) 0)})
  (is (deep= @{:width 1264
               :height 1680
               :pixel-format :gray8
               :has-black? true
               :has-white? true
               :many-shades? true
               :substantial-ink? true
               :non-empty? true}
             observed)
      "Janet demo scene renders through the public skia API in portrait Kobo dimensions"))

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
