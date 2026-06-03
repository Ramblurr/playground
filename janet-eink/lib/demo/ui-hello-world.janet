# First UI application: retained UI label, rect, gap, and padding demo.

(import ../skia :as skia)
(import ../ui :as ui)
(import ../ui/nodes :as nodes)

(defn view
  []
  [ui/rect {:paint "E" :radius [32 20 8 8 32 20 8 8]}
   [ui/padding {:horizontal 48 :vertical 32}
    [ui/rect {:paint "F" :radius [18 12]}
     [ui/padding {:left 28 :top 18 :right 28 :bottom 18}
      [ui/label {:font-family "Noto Sans"
                 :font-size 88
                 :paint "F00"}
       "Hello, world."]]]]])

(defn gap-view
  []
  [ui/rect {:paint "80" :radius [8 4]}
   [ui/gap {:width 420 :height 18}]])

(defn- measure-node
  [canvas node]
  (ui/measure canvas node {:w (skia/width canvas) :h (skia/height canvas)}))

(defn draw
  "Draws the hello-world UI into an existing canvas."
  [canvas]
  (let [w (skia/width canvas)
        h (skia/height canvas)
        main-node (ui/make (view))
        gap-node (ui/make (gap-view))
        main-size (measure-node canvas main-node)
        gap-size (measure-node canvas gap-node)
        gap-y-spacing 28
        total-h (+ (get main-size :h) gap-y-spacing (get gap-size :h))
        main-x (math/round (/ (- w (get main-size :w)) 2))
        main-y (math/round (/ (- h total-h) 2))
        gap-x (math/round (/ (- w (get gap-size :w)) 2))
        gap-y (+ main-y (get main-size :h) gap-y-spacing)]
    (skia/clear canvas "F")
    (ui/draw canvas main-node (nodes/make-bounds main-x main-y (get main-size :w) (get main-size :h)))
    (ui/draw canvas gap-node (nodes/make-bounds gap-x gap-y (get gap-size :w) (get gap-size :h)))
    canvas))

(defn run
  "Creates the default platform canvas, draws the demo, and presents it."
  [& _args]
  (let [canvas (skia/create)]
    (draw canvas)
    (skia/present canvas {:block? true})
    canvas))
