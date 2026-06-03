(use ../deps/testament)
(import ../lib/ui/core :as ui-core)
(import ../lib/skia :as skia)
(import ../lib/ui :as ui)
(import ../lib/ui/nodes :as nodes)

(deftest ui-core-scale-helpers-rounding-rules
  (def observed
    @{:default-scale (ui-core/scale @{})
      :explicit-scale (ui-core/scale {:scale 1.5})
      :scaled-default (ui-core/scaled @{} 4.2)
      :scaled-fractional (ui-core/scaled {:scale 1.5} 10.1)
      :descaled-default (ui-core/descaled @{} 9)
      :descaled-fractional (ui-core/descaled {:scale 2} 9)
      :descaled-nil (ui-core/descaled {:scale 2} nil)
      :dimension-round-down (ui-core/dimension {:scale 2} 10.24 {:w 100 :h 50})
      :dimension-round-up (ui-core/dimension {:scale 2} 10.26 {:w 100 :h 50})
      :function-dimension (ui-core/dimension {:scale 2}
                                             (fn [cs]
                                               (+ (get cs :width) (get cs :height)))
                                             {:w 20 :h 10})})
  (is (deep= @{:default-scale 1
               :explicit-scale 1.5
               :scaled-default 5
               :scaled-fractional 16
               :descaled-default 9
               :descaled-fractional 4.5
               :descaled-nil nil
               :dimension-round-down 20
               :dimension-round-up 21
               :function-dimension 30}
             observed)
      "UI scale helpers convert logical dimensions into device pixels with rounding"))

(defn font-dir
  []
  (or (os/getenv "OTTER_FONT_DIR")
      (skia/default-font-dir)))

(defn test-canvas
  []
  (skia/create {:width 320 :height 120 :font-dir (font-dir)}))

(deftest ui-label-measures-and-draws-shaped-text
  (def frame (test-canvas))
  (skia/clear frame {:gray skia/white})
  (def node (ui/make [ui/label {:font-size 24 :paint skia/black} "Hello" " UI"]))
  (def size (ui/measure frame node {:w 320 :h 120}))
  (def metrics (skia/text-line-metrics (get node :text-line)))
  (def before (skia/stats frame))
  (ui/draw frame node (nodes/make-bounds 4 5 (get size :w) (get size :h)))
  (def after (skia/stats frame))
  (def bounds (get node :bounds))
  (def observed
    @{:positive-size? (and (> (get size :w) 0) (> (get size :h) 0))
      :height-matches-text-line? (= (get size :h) (get metrics :height))
      :text (get node :text)
      :bounds @{:x (get bounds :x)
                :y (get bounds :y)
                :w (get bounds :w)
                :h (get bounds :h)}
      :draw-mutated? (> (get after :non-white-pixels)
                        (get before :non-white-pixels))})
  (is (deep= @{:positive-size? true
               :height-matches-text-line? true
               :text "Hello UI"
               :bounds @{:x 4 :y 5 :w (get size :w) :h (get size :h)}
               :draw-mutated? true}
             observed)
      "ui/label measures with shaped cap-height metrics and draws a retained node"))

(deftest ui-label-reconcile-reuses-node-and-reshapes-when-shape-key-changes
  (def frame (test-canvas))
  (def ctx @{:canvas frame :scale 1})
  (def node (ui/reconcile nil ctx [ui/label {:font-size 20} "Hello"]))
  (nodes/measure node ctx {:w 320 :h 120})
  (def line1 (get node :text-line))
  (def same (ui/reconcile node ctx [ui/label {:font-size 20} "Hello"]))
  (nodes/measure same ctx {:w 320 :h 120})
  (def line2 (get same :text-line))
  (def text-changed (ui/reconcile same ctx [ui/label {:font-size 20} "World"]))
  (nodes/measure text-changed ctx {:w 320 :h 120})
  (def line3 (get text-changed :text-line))
  (def font-size-changed (ui/reconcile text-changed ctx [ui/label {:font-size 24} "World"]))
  (nodes/measure font-size-changed ctx {:w 320 :h 120})
  (def line4 (get font-size-changed :text-line))
  (def weight-changed (ui/reconcile font-size-changed ctx [ui/label {:font-size 24 :font-weight 700} "World"]))
  (nodes/measure weight-changed ctx {:w 320 :h 120})
  (def line5 (get weight-changed :text-line))
  (def features-changed (ui/reconcile weight-changed ctx [ui/label {:font-size 24 :font-weight 700 :font-features ["tnum"]} "World"]))
  (nodes/measure features-changed ctx {:w 320 :h 120})
  (def line6 (get features-changed :text-line))
  (def scaled-ctx @{:canvas frame :scale 2})
  (def scale-changed (ui/reconcile features-changed scaled-ctx [ui/label {:font-size 24 :font-weight 700 :font-features ["tnum"]} "World"]))
  (nodes/measure scale-changed scaled-ctx {:w 320 :h 120})
  (def line7 (get scale-changed :text-line))
  (def observed
    @{:node-reused? (and (= node same)
                         (= same text-changed)
                         (= text-changed font-size-changed)
                         (= font-size-changed weight-changed)
                         (= weight-changed features-changed)
                         (= features-changed scale-changed))
      :same-shape-line-reused? (= line1 line2)
      :text-reshaped? (not= line2 line3)
      :font-size-reshaped? (not= line3 line4)
      :weight-reshaped? (not= line4 line5)
      :features-reshaped? (not= line5 line6)
      :scale-reshaped? (not= line6 line7)})
  (is (deep= @{:node-reused? true
               :same-shape-line-reused? true
               :text-reshaped? true
               :font-size-reshaped? true
               :weight-reshaped? true
               :features-reshaped? true
               :scale-reshaped? true}
             observed)
      "label reconciliation keeps nodes while replacing shaped lines only when shape inputs change"))

(deftest ui-render-renders-one-label-through-public-facade
  (def frame (test-canvas))
  (skia/clear frame {:gray skia/white})
  (def before (skia/stats frame))
  (def node (ui/render frame [ui/label {:font-size 24 :paint skia/black} "Hello shaped UI"]))
  (def after (skia/stats frame))
  (def observed
    @{:kind (get node :kind)
      :has-bounds? (nodes/bounds? (get node :bounds))
      :draw-mutated? (> (get after :non-white-pixels)
                        (get before :non-white-pixels))})
  (is (deep= @{:kind :label
               :has-bounds? true
               :draw-mutated? true}
             observed)
      "ui/render can render one label through the public UI facade"))

(run-tests!)
