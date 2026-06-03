# First UI application: retained UI layout-node demo.

(import ../skia :as skia)
(import ../ui :as ui)
(import ../ui/nodes :as nodes)

(def darkest "20")
(def darker "40")
(def dark "60")

(defn swatch
  [paint width height]
  [ui/rect {:paint paint :radius [8 4]}
   [ui/gap {:width width :height height}]])

(defn grayscale-column
  []
  [ui/column {:gap 8}
   [swatch darkest 120 30]
   [swatch darker 120 30]
   [swatch dark 120 30]])

(defn grayscale-row
  []
  [ui/row {:gap 8 :align :center}
   [swatch darkest 100 30]
   [swatch darker 100 30]
   [swatch dark 100 30]])

(defn view
  []
  [ui/column {:gap 28 :align :center}
   [ui/rect {:paint "E" :radius [32 20 8 8 32 20 8 8]}
    [ui/padding {:horizontal 48 :vertical 32}
     [ui/rect {:paint "F" :radius [18 12]}
      [ui/padding {:left 28 :top 18 :right 28 :bottom 18}
       [ui/label {:font-family "Noto Sans"
                  :font-size 88
                  :paint "F00"}
        "Hello, world."]]]]]
   [ui/row {:gap 36 :align :top}
    [grayscale-column]
    [grayscale-row]]])

(defn draw
  "Draws the hello-world UI into an existing canvas."
  [canvas]
  (let [w (skia/width canvas)
        h (skia/height canvas)
        node (ui/make (view))
        size (ui/measure canvas node {:w w :h h})
        x (math/round (/ (- w (get size :w)) 2))
        y (math/round (/ (- h (get size :h)) 2))]
    (skia/clear canvas "F")
    (ui/draw canvas node (nodes/make-bounds x y (get size :w) (get size :h)))
    canvas))

(defn run
  "Creates the default platform canvas, draws the demo, and presents it."
  [& _args]
  (let [canvas (skia/create)]
    (draw canvas)
    (skia/present canvas {:block? true})
    canvas))
