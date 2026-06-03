# Public UI facade for retained Otter widgets.

(import ./skia :as skia)
(import ./ui/label :as label-node)
(import ./ui/nodes :as nodes)
(import ./ui/reconcile :as reconcile-node)
(import ./ui/rect :as rect-node)

(def label label-node/label)
(def rect rect-node/rect)
(def make reconcile-node/make)
(def reconcile reconcile-node/reconcile)
(def reconcile-many reconcile-node/reconcile-many)

(defn- ctx
  [canvas opts viewport]
  (let [options (or opts @{})]
    (merge options @{:canvas canvas
                     :viewport viewport
                     :scale (get options :scale 1)})))

(defn- viewport-bounds
  [canvas opts]
  (or (get opts :bounds nil)
      (nodes/make-bounds 0 0 (skia/width canvas) (skia/height canvas))))

(defn measure
  [canvas node cs &opt opts]
  (let [bounds (viewport-bounds canvas (or opts @{}))]
    (nodes/measure node (ctx canvas opts bounds) cs)))

(defn draw
  [canvas node bounds &opt opts]
  (nodes/draw node (ctx canvas opts bounds) bounds)
  node)

(defn render
  [canvas element &opt opts]
  (let [options (or opts @{})
        bounds (viewport-bounds canvas options)
        context (ctx canvas options bounds)
        node (make element)
        size (nodes/measure node context (nodes/make-size (get bounds :w) (get bounds :h)))
        draw-bounds (nodes/make-bounds (get bounds :x) (get bounds :y) (get size :w) (get size :h))]
    (nodes/draw node context draw-bounds)
    node))
