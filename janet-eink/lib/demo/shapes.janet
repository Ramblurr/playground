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
  (var x 60)
  (each shade shades
    (skia/draw-rect canvas x 100 120 180 shade)
    (set x (+ x 145))))

(defn draw-cards
  [canvas]
  (skia/draw-rounded-rect canvas 80 360 360 180 24 224)
  (skia/draw-rounded-rect canvas 110 390 300 45 12 96)
  (skia/draw-rect canvas 110 460 250 35 160)
  (skia/draw-rect canvas 110 510 180 24 32)
  (skia/draw-rounded-rect canvas 500 350 420 220 36 192)
  (skia/draw-circle canvas 590 460 70 64)
  (skia/draw-circle canvas 760 460 70 128)
  (skia/draw-rounded-rect canvas 80 620 420 180 18 160)
  (skia/draw-rect canvas 110 660 360 30 32)
  (skia/draw-rect canvas 110 715 280 30 96)
  (skia/draw-rect canvas 110 770 200 20 224))

(defn draw-triangles
  [canvas]
  (skia/draw-triangle canvas 80 1360 205 1060 330 1360 32)
  (skia/draw-triangle canvas 340 1380 465 1080 590 1380 96)
  (skia/draw-triangle canvas 600 1380 725 1080 850 1380 160)
  (skia/draw-triangle canvas 860 1380 985 1080 1110 1380 224))

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
