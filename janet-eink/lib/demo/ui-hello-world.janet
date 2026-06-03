# First UI application: retained UI layout-node demo.

(import ../skia :as skia)
(import ../ui :as ui)
(import ../ui/nodes :as nodes)

(def darkest "20")
(def darker "40")
(def dark "60")
(def mid "80")
(def light "C")

(defn swatch
  [paint width height]
  [ui/rect {:paint paint :radius [8 4]}
   [ui/gap {:width width :height height}]])

(defn overlay-card
  []
  [ui/stack
   [ui/rect {:paint "E" :radius [32 20]}
    [ui/gap {:width 520 :height 150}]]
   [ui/align {:x :center :y :center}
    [ui/label {:font-family "Noto Sans"
               :font-size 46
               :paint "0"}
     "stack + align"]]
   [ui/align {:x :right :y :top :child-x :right :child-y :top}
    [ui/rect {:paint "0" :radius [8 6]}
     [ui/padding {:horizontal 12 :vertical 6}
      [ui/label {:font-family "Noto Sans"
                 :font-size 18
                 :paint "F"}
       "overlay"]]]]])

(defn grow-demo
  []
  [ui/rect {:paint [{:fill "F"} {:stroke "80" :width 1}] :radius [16 10]}
   [ui/padding {:padding 16}
    [ui/column {:gap 10}
     [ui/label {:font-family "Noto Sans"
                :font-size 24
                :paint "0"}
      "ui/grow: leftover row space splits 1:2"]
     [ui/row {:gap 8 :align :center}
      [swatch darkest 70 30]
      [ui/grow 1
       [ui/rect {:paint light :radius [8 4]}
        [ui/gap {:height 30}]]]
      [ui/grow 2
       [ui/rect {:paint mid :radius [8 4]}
        [ui/gap {:height 30}]]]
      [swatch darker 70 30]]]]])

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
  [ui/column {:gap 24 :align :center}
   [overlay-card]
   [grow-demo]
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
