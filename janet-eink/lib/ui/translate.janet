# Draw-time translation wrapper node.

(import ./core :as core)
(import ./element :as elem)
(import ./nodes :as nodes)


(defn- dimension-or-zero
  [ctx props bounds key]
  (let [value (get props key 0)]
    (core/dimension ctx value bounds)))

(defn- validate-translate-props!
  [props]
  (each key [:dx :dy]
    (when (has-key? props key)
      (unless (core/dimension? (get props key))
        (error (string "translate: " key " expected number or function dimension, got " (type (get props key)))))))
  props)

(defn- translate-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (let [props (get self :props @{})
        dx (dimension-or-zero ctx props bounds :dx)
        dy (dimension-or-zero ctx props bounds :dy)
        child-bounds (nodes/make-bounds (+ (get bounds :x) dx)
                                        (+ (get bounds :y) dy)
                                        (get bounds :w)
                                        (get bounds :h))]
    (when-let [child (get self :child nil)]
      (nodes/draw child ctx child-bounds)))
  self)

(def TranslateNode
  (table/setproto @{:draw translate-draw}
                  nodes/WrapperNode))

(defn translate
  "Creates a wrapper that draws its child offset from its assigned bounds.

  Forms:
      [translate {:dx 12} child]
      [translate {:dy 8} child]
      [translate {:dx 12 :dy 8} child]

  Options:
      :dx number | function - horizontal logical offset, default 0
      :dy number | function - vertical logical offset, default 0

  Measurement delegates to the child. Drawing stores the wrapper's original bounds
  and draws the child into bounds shifted by the resolved offset."
  [& args]
  (let [props (elem/require-props! "translate" args)
        [_parsed-props children] (elem/parse-args args "translate")]
    (validate-translate-props! props)
    (elem/expect-one-child! "translate" children)
    (nodes/make-node TranslateNode :translate props @{:ui/builtin? true
                                                      :constructor translate})))
