# Scoped rectangular clip wrapper node.

(import ../skia :as skia)
(import ./core :as core)
(import ./element :as elem)
(import ./nodes :as nodes)


(defn- radius-seq?
  [value]
  (or (array? value) (tuple? value)))

(defn- radius-error
  [detail]
  (error (string "clip: :radius expected nil, a number, or an array/tuple of 1, 2, 4, or 8 numbers" detail)))

(defn- number-radius!
  [value]
  (unless (= :number (type value))
    (radius-error (string "; got " (type value))))
  value)

(defn- validate-radius!
  [radius]
  (cond
    (nil? radius) nil
    (= :number (type radius)) radius
    (radius-seq? radius)
    (do
      (unless (or (= 1 (length radius))
                  (= 2 (length radius))
                  (= 4 (length radius))
                  (= 8 (length radius)))
        (radius-error (string " with " (length radius) " item(s)")))
      (each item radius
        (number-radius! item))
      radius)
    :else
    (radius-error (string "; got " (type radius)))))

(defn- scaled-radius
  [ctx bounds radius]
  (nodes/clamp-nonnegative (core/dimension ctx (number-radius! radius) bounds)))

(defn- scaled-radii
  [ctx bounds radii]
  (case (length radii)
    1 (let [r (scaled-radius ctx bounds (get radii 0))]
        @[r r r r r r r r])
    2 (let [rx (scaled-radius ctx bounds (get radii 0))
            ry (scaled-radius ctx bounds (get radii 1))]
        @[rx ry rx ry rx ry rx ry])
    4 (let [tl (scaled-radius ctx bounds (get radii 0))
            tr (scaled-radius ctx bounds (get radii 1))
            br (scaled-radius ctx bounds (get radii 2))
            bl (scaled-radius ctx bounds (get radii 3))]
        @[tl tl tr tr br br bl bl])
    8 (let [out @[]]
        (each item radii
          (array/push out (scaled-radius ctx bounds item)))
        out)
    (radius-error (string " with " (length radii) " item(s)"))))

(defn- resolved-radii
  [ctx bounds radius]
  (let [validated (validate-radius! radius)]
    (cond
      (nil? validated) nil
      (= :number (type validated))
      (let [r (scaled-radius ctx bounds validated)]
        @[r r r r r r r r])
      :else
      (scaled-radii ctx bounds validated))))

(defn- apply-clip!
  [ctx bounds]
  (let [props (get ctx :clip-props @{})
        radius (get props :radius nil)
        canvas (get ctx :canvas nil)]
    (unless canvas
      (error "clip: draw requires ctx :canvas"))
    (if (resolved-radii ctx bounds radius)
      (error "clip: :radius requires skia/clip-rrect; rectangular clipping is available without :radius")
      (skia/clip-rect canvas (get bounds :x) (get bounds :y) (get bounds :w) (get bounds :h)))))

(defn- clip-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (let [canvas (get ctx :canvas nil)
        clip-ctx (merge ctx @{:clip-props (get self :props @{})})]
    (unless canvas
      (error "clip: draw requires ctx :canvas"))
    (when (and (> (get bounds :w) 0) (> (get bounds :h) 0))
      (skia/save canvas)
      (let [result (protect
                     (do
                       (apply-clip! clip-ctx bounds)
                       (when-let [child (get self :child nil)]
                         (nodes/draw child ctx bounds))))]
        (skia/restore canvas)
        (unless (get result 0)
          (error (get result 1))))))
  self)

(def ClipNode
  (table/setproto @{:draw clip-draw}
                  nodes/WrapperNode))

(defn clip
  "Creates a wrapper that clips child drawing to its assigned bounds.

  Forms:
      [clip child]
      [clip {} child]
      [clip {:radius 8} child]

  Rectangular clipping uses the current Skia clip stack and is scoped with
  save/restore. Rounded clipping follows the same radius grammar as rect, but requires
  a `skia/clip-rrect` binding; without that native support, :radius fails clearly
  instead of silently approximating rounded clips with a rectangle."
  [& args]
  (let [[props children] (elem/parse-args args "clip")]
    (validate-radius! (get props :radius nil))
    (elem/expect-one-child! "clip" children)
    (nodes/make-node ClipNode :clip props @{:ui/builtin? true
                                            :constructor clip})))
