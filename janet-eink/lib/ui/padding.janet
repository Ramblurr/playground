# Padding wrapper node.

(import ./core :as core)
(import ./element :as elem)
(import ./nodes :as nodes)


(defn- dimension-option!
  [who value]
  (unless (core/dimension? value)
    (error (string who ": expected number or function dimension, got " (type value))))
  value)

(defn- padding-value
  [props side axis]
  (or (get props side nil)
      (get props axis nil)
      (get props :padding nil)
      0))

(defn- padding-specs
  [props]
  {:left (padding-value props :left :horizontal)
   :top (padding-value props :top :vertical)
   :right (padding-value props :right :horizontal)
   :bottom (padding-value props :bottom :vertical)})

(defn- validate-padding!
  [props]
  (let [specs (padding-specs props)]
    (each key [:left :top :right :bottom]
      (dimension-option! (string "padding " key) (get specs key))))
  props)

(defn- resolved-padding
  [ctx props cs]
  (let [specs (padding-specs props)]
    {:left (nodes/clamp-nonnegative (core/dimension ctx (get specs :left) cs))
     :top (nodes/clamp-nonnegative (core/dimension ctx (get specs :top) cs))
     :right (nodes/clamp-nonnegative (core/dimension ctx (get specs :right) cs))
     :bottom (nodes/clamp-nonnegative (core/dimension ctx (get specs :bottom) cs))}))

(defn- inner-size
  [cs padding]
  (nodes/make-size (- (get cs :w) (get padding :left) (get padding :right))
                   (- (get cs :h) (get padding :top) (get padding :bottom))))

(defn- add-padding
  [size padding]
  (nodes/make-size (+ (get size :w) (get padding :left) (get padding :right))
                   (+ (get size :h) (get padding :top) (get padding :bottom))))

(defn- padding-measure
  [self ctx cs]
  (let [padding (resolved-padding ctx (get self :props @{}) cs)
        child-size (nodes/measure (get self :child nil) ctx (inner-size cs padding))]
    (add-padding child-size padding)))

(defn- padding-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (let [padding (resolved-padding ctx (get self :props @{}) bounds)
        child-bounds (nodes/make-bounds (+ (get bounds :x) (get padding :left))
                                        (+ (get bounds :y) (get padding :top))
                                        (- (get bounds :w) (get padding :left) (get padding :right))
                                        (- (get bounds :h) (get padding :top) (get padding :bottom)))]
    (when-let [child (get self :child nil)]
      (nodes/draw child ctx child-bounds)))
  self)

(def PaddingNode
  (table/setproto @{:measure padding-measure
                    :draw padding-draw}
                  nodes/WrapperNode))

(defn padding
  "Creates a padding wrapper node.

  Forms:
      [padding {:padding 12} child]
      [padding {:horizontal 10 :vertical 6} child]
      [padding {:left 4 :top 8 :right 4 :bottom 8} child]

  Options:
      :padding    number | function - equal padding on all sides
      :horizontal number | function - left and right padding
      :vertical   number | function - top and bottom padding
      :left       number | function - left padding
      :right      number | function - right padding
      :top        number | function - top padding
      :bottom     number | function - bottom padding

  More specific values override broader ones: side > axis > :padding > 0.
  Dimensions are logical UI units, scaled through the render context."
  [& args]
  (let [props (elem/require-props! "padding" args)
        [_parsed-props children] (elem/parse-args args "padding")]
    (validate-padding! props)
    (elem/expect-one-child! "padding" children)
    (nodes/make-node PaddingNode :padding props @{:ui/builtin? true
                                                  :constructor padding})))
