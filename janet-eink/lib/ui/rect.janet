# Filled rectangle wrapper node.

(import ../skia :as skia)
(import ./core :as core)
(import ./element :as elem)
(import ./nodes :as nodes)


(defn- require-paint!
  [props]
  (unless (has-key? props :paint)
    (error "rect: props must include :paint"))
  (get props :paint))

(defn- radius-seq?
  [value]
  (or (array? value) (tuple? value)))

(defn- radius-error
  [detail]
  (error (string "rect: :radius expected nil, a number, or an array/tuple of 1, 2, 4, or 8 numbers" detail)))

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

(defn- rect-measure
  [self ctx cs]
  (if-let [child (get self :child nil)]
    (nodes/measure child ctx cs)
    (nodes/zero-size)))

(defn- draw-background
  [self ctx bounds]
  (let [props (get self :props @{})
        paint (require-paint! props)
        canvas (get ctx :canvas nil)
        x (get bounds :x)
        y (get bounds :y)
        w (get bounds :w)
        h (get bounds :h)]
    (unless canvas
      (error "rect: draw requires ctx :canvas"))
    (if-let [radii (resolved-radii ctx bounds (get props :radius nil))]
      (skia/draw-rrect canvas x y w h radii {:paint paint})
      (skia/draw-rect canvas x y w h {:paint paint}))))

(defn- rect-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (draw-background self ctx bounds)
  (when-let [child (get self :child nil)]
    (nodes/draw child ctx bounds))
  self)

(def RectNode
  (table/setproto @{:measure rect-measure
                    :draw rect-draw}
                  nodes/WrapperNode))

(defn rect
  "Creates a filled rectangle wrapper node.

  Forms:
      [rect {:paint \"F\"}]
      [rect {:paint \"E\" :radius 8} child]
      [rect {:paint \"E\" :radius [12 8]} child]
      [rect {:paint \"E\" :radius [8 8 0 0]} child]
      [rect {:paint \"E\" :radius [12 8 4 4 0 0 12 8]} child]

  Options:
      :paint  paint-spec - rectangle paint; required
      :radius nil | number | [number ...]
        nil: square corners
        number or [r]: same x/y radius for every corner
        [rx ry]: same x/y radii for every corner
        [tl tr br bl]: per-corner circular radii in clockwise order
        [tlx tly trx try brx bry blx bly]: per-corner elliptical radii
          in clockwise order from top-left

  The rectangle measures to its child size, or zero when childless. It always
  fills the exact bounds it receives before drawing its optional child."
  [& args]
  (let [props (elem/require-props! "rect" args)
        [_parsed-props children] (elem/parse-args args "rect")]
    (require-paint! props)
    (validate-radius! (get props :radius nil))
    (elem/expect-zero-or-one-child! "rect" children)
    (nodes/make-node RectNode :rect props @{:ui/builtin? true
                                            :constructor rect})))
