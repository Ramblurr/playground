# Fixed-dimension wrapper node.

(import ./core :as core)
(import ./element :as elem)
(import ./nodes :as nodes)


(defn- explicit-dimension
  [props key]
  (get props key nil))

(defn- dimension-specs
  [props]
  {:width (or (explicit-dimension props :width)
              (explicit-dimension props :size))
   :height (or (explicit-dimension props :height)
               (explicit-dimension props :size))})

(defn- validate-dimension!
  [who value]
  (when (not (nil? value))
    (unless (core/dimension? value)
      (error (string "size: " who " expected number or function dimension, got " (type value)))))
  value)

(defn- validate-size-props!
  [props]
  (validate-dimension! ":width" (get props :width nil))
  (validate-dimension! ":height" (get props :height nil))
  (validate-dimension! ":size" (get props :size nil))
  props)

(defn- resolved-dimensions
  [self ctx cs]
  (let [specs (dimension-specs (get self :props @{}))
        width-spec (get specs :width nil)
        height-spec (get specs :height nil)]
    {:width (when (not (nil? width-spec))
              (nodes/clamp-nonnegative (core/dimension ctx width-spec cs)))
     :height (when (not (nil? height-spec))
               (nodes/clamp-nonnegative (core/dimension ctx height-spec cs)))}))

(defn- size-measure
  [self ctx cs]
  (let [dims (resolved-dimensions self ctx cs)
        width (get dims :width nil)
        height (get dims :height nil)
        child (get self :child nil)]
    (cond
      (and (not (nil? width)) (not (nil? height)))
      (nodes/make-size width height)

      (and (not (nil? width)) child)
      (let [child-size (nodes/measure child ctx (nodes/make-size width (get cs :h)))]
        (nodes/make-size width (get child-size :h)))

      (and (not (nil? height)) child)
      (let [child-size (nodes/measure child ctx (nodes/make-size (get cs :w) height))]
        (nodes/make-size (get child-size :w) height))

      (not (nil? width))
      (nodes/make-size width 0)

      (not (nil? height))
      (nodes/make-size 0 height)

      :else
      (nodes/zero-size))))

(defn- size-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (when-let [child (get self :child nil)]
    (nodes/draw child ctx bounds))
  self)

(def SizeNode
  (table/setproto @{:measure size-measure
                    :draw size-draw}
                  nodes/WrapperNode))

(defn size
  "Creates a wrapper that fixes one or both measured dimensions.

  Forms:
      [size child]
      [size {:width 120} child]
      [size {:height 80} child]
      [size {:size 48} child]
      [size {:size 48 :width 96} child]

  Options:
      :width  number | function - fixed measured width
      :height number | function - fixed measured height
      :size   number | function - fallback for both width and height

  Side-specific dimensions override :size. With no fixed dimensions, size
  measures to zero."
  [& args]
  (let [[props children] (elem/parse-args args "size")]
    (validate-size-props! props)
    (elem/expect-one-child! "size" children)
    (nodes/make-node SizeNode :size props @{:ui/builtin? true
                                            :constructor size})))
