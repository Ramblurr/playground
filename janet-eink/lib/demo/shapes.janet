(import ../skia :as skia)

(defn draw-border
  [canvas w h]
  (skia/draw-rect canvas 0 0 w 6 skia/black)
  (skia/draw-rect canvas 0 (- h 6) w 6 skia/black)
  (skia/draw-rect canvas 0 0 6 h skia/black)
  (skia/draw-rect canvas (- w 6) 0 6 h skia/black))

(defn draw-gray-bars
  [canvas]
  (def shades [0 32 64 96 128 160 192 224])
  (var x 80)
  (each shade shades
    (skia/draw-rect canvas x 100 150 180 shade)
    (set x (+ x 180))))

(defn draw-cards
  [canvas]
  (skia/draw-rounded-rect canvas 100 360 360 180 24 224)
  (skia/draw-rounded-rect canvas 130 390 300 45 12 96)
  (skia/draw-rect canvas 130 460 250 35 160)
  (skia/draw-rect canvas 130 510 180 24 32)
  (skia/draw-rounded-rect canvas 560 350 420 220 36 192)
  (skia/draw-circle canvas 650 460 70 64)
  (skia/draw-circle canvas 820 460 70 128)
  (skia/draw-rounded-rect canvas 1060 360 420 180 18 160)
  (skia/draw-rect canvas 1090 400 360 30 32)
  (skia/draw-rect canvas 1090 455 280 30 96)
  (skia/draw-rect canvas 1090 510 200 20 224))

(defn draw-triangles
  [canvas]
  (skia/draw-triangle canvas 180 920 360 620 540 920 32)
  (skia/draw-triangle canvas 520 940 700 640 880 940 96)
  (skia/draw-triangle canvas 860 940 1040 640 1220 940 160)
  (skia/draw-triangle canvas 1200 940 1380 640 1560 940 224))

(defn draw
  [canvas]
  (def w (skia/width canvas))
  (def h (skia/height canvas))
  (skia/clear canvas skia/white)
  (draw-gray-bars canvas)
  (draw-cards canvas)
  (draw-triangles canvas)
  (draw-border canvas w h)
  canvas)
