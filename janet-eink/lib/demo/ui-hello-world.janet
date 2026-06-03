# First UI application: a retained UI label on a rounded rect background.

(import ../skia :as skia)
(import ../ui :as ui)
(import ../ui/nodes :as nodes)

(defn view
  []
  [ui/rect {:paint "E" :radius [32 20 8 8 32 20 8 8]}
   [ui/label {:font-family "Noto Sans"
              :font-size 88
              :paint "F00"}
    "Hello, world."]])

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
