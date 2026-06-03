# Anchor-based alignment wrapper node.

(import ./element :as elem)
(import ./nodes :as nodes)


(def x-anchors
  {:left 0
   :center 0.5
   :right 1})

(def y-anchors
  {:top 0
   :center 0.5
   :bottom 1})

(defn- factor-number!
  [who value]
  (unless (and (= :number (type value)) (>= value 0) (<= value 1))
    (error (string "align: " who " expected a number from 0 to 1, got " (type value))))
  value)

(defn- normalize-anchor
  [who options value]
  (cond
    (nil? value)
    nil

    (= :number (type value))
    (factor-number! who value)

    :else
    (let [factor (get options value nil)]
      (if (nil? factor)
        (error (string "align: " who " expected one of " (keys options) " or a number from 0 to 1, got " value))
        factor))))

(defn- resolve-anchors
  [props]
  (let [x (normalize-anchor ":x" x-anchors (get props :x nil))
        y (normalize-anchor ":y" y-anchors (get props :y nil))]
    (unless (or (not (nil? x)) (not (nil? y)))
      (error "align: expected props to include :x, :y, or both"))
    {:x x
     :y y
     :child-x (or (normalize-anchor ":child-x" x-anchors (get props :child-x nil)) x)
     :child-y (or (normalize-anchor ":child-y" y-anchors (get props :child-y nil)) y)}))

(defn- align-measure
  [self ctx cs]
  (nodes/measure (get self :child nil) ctx cs))

(defn- anchor-position
  [origin extent parent-anchor child-extent child-anchor]
  (math/round (- (+ origin (* extent parent-anchor))
                 (* child-extent child-anchor))))

(defn- align-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (when-let [child (get self :child nil)]
    (let [child-size (nodes/measure child ctx (nodes/make-size (get bounds :w) (get bounds :h)))
          x (get self :x nil)
          y (get self :y nil)
          child-x (get self :child-x nil)
          child-y (get self :child-y nil)
          child-bounds (cond
                         (and (not (nil? x)) (not (nil? y)))
                         (nodes/make-bounds (anchor-position (get bounds :x) (get bounds :w) x (get child-size :w) child-x)
                                            (anchor-position (get bounds :y) (get bounds :h) y (get child-size :h) child-y)
                                            (get child-size :w)
                                            (get child-size :h))

                         (not (nil? x))
                         (nodes/make-bounds (anchor-position (get bounds :x) (get bounds :w) x (get child-size :w) child-x)
                                            (get bounds :y)
                                            (get child-size :w)
                                            (get bounds :h))

                         (not (nil? y))
                         (nodes/make-bounds (get bounds :x)
                                            (anchor-position (get bounds :y) (get bounds :h) y (get child-size :h) child-y)
                                            (get bounds :w)
                                            (get child-size :h))

                         :else
                         bounds)]
      (nodes/draw child ctx child-bounds)))
  self)

(def AlignNode
  (table/setproto @{:measure align-measure
                    :draw align-draw}
                  nodes/WrapperNode))

(defn align
  "Creates an anchor-based alignment wrapper.

  Forms:
      [align {:x :center} child]
      [align {:y :center} child]
      [align {:x :right :y :bottom} child]
      [align {:x 0.7 :child-x 0.2} child]

  Options:
      :x       :left | :center | :right | number 0..1
      :y       :top | :center | :bottom | number 0..1
      :child-x :left | :center | :right | number 0..1
      :child-y :top | :center | :bottom | number 0..1

  Missing child anchors default to the corresponding parent anchor. With only :x,
  the child keeps the assigned height. With only :y, the child keeps the assigned
  width. With both axes, the child draws at its natural measured size."
  [& args]
  (let [props (elem/require-props! "align" args)
        [_parsed-props children] (elem/parse-args args "align")
        anchors (resolve-anchors props)]
    (elem/expect-one-child! "align" children)
    (nodes/make-node AlignNode :align props @{:ui/builtin? true
                                              :constructor align
                                              :x (get anchors :x nil)
                                              :y (get anchors :y nil)
                                              :child-x (get anchors :child-x nil)
                                              :child-y (get anchors :child-y nil)})))
