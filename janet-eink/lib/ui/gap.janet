# Empty terminal spacer node.

(import ./core :as core)
(import ./element :as elem)
(import ./nodes :as nodes)


(defn- validate-dimension-option!
  [props key]
  (when (has-key? props key)
    (let [value (get props key)]
      (unless (core/dimension? value)
        (error (string "gap: " key " expected number or function dimension, got " (type value))))))
  props)

(defn- dimension-or-zero
  [ctx props cs key]
  (let [value (get props key 0)]
    (nodes/clamp-nonnegative (core/dimension ctx value cs))))

(defn- gap-measure
  [self ctx cs]
  (let [props (get self :props @{})]
    (nodes/make-size (dimension-or-zero ctx props cs :width)
                     (dimension-or-zero ctx props cs :height))))

(defn- gap-draw
  [self _ctx bounds]
  (nodes/store-bounds! self bounds)
  self)

(def GapNode
  (table/setproto @{:measure gap-measure
                    :draw gap-draw}
                  nodes/TerminalNode))

(defn gap
  "Creates an empty spacer node.

  Forms:
      [gap]
      [gap {:width 10}]
      [gap {:height 12}]
      [gap {:width 10 :height 12}]

  Width and height are logical UI dimensions, scaled through the render context.
  Missing dimensions default to zero. Gap draws nothing but records its bounds."
  [& args]
  (let [[props children] (elem/parse-args args "gap")]
    (validate-dimension-option! props :width)
    (validate-dimension-option! props :height)
    (elem/expect-no-children! "gap" children)
    (nodes/make-node GapNode :gap props @{:ui/builtin? true
                                          :constructor gap})))
