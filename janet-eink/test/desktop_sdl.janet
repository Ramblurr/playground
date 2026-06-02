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

(deftest janet-demo-scene-renders-kobo-sized-gray-shape-screen
  (def frame (skia/create 1680 1264))
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
  (is (deep= @{:width 1680
               :height 1264
               :pixel-format :gray8
               :has-black? true
               :has-white? true
               :many-shades? true
               :substantial-ink? true
               :non-empty? true}
             observed)
      "Janet demo scene renders through the public skia API"))

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
