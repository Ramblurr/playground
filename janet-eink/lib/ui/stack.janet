# Overlay container node.

(import ./element :as elem)
(import ./nodes :as nodes)


(defn- stack-measure
  [self ctx cs]
  (var max-w 0)
  (var max-h 0)
  (each child (get self :children @[])
    (let [size (nodes/measure child ctx cs)]
      (set max-w (max max-w (get size :w)))
      (set max-h (max max-h (get size :h)))))
  (nodes/make-size max-w max-h))

(defn- stack-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (each child (get self :children @[])
    (nodes/draw child ctx bounds))
  self)

(def StackNode
  (table/setproto @{:measure stack-measure
                    :draw stack-draw}
                  nodes/ContainerNode))

(defn stack
  "Creates an overlay container node.

  Forms:
      [stack child ...]
      [stack {:key k} child ...]

  Each child measures under the same constraints. Stack measures to the maximum
  child width and height, then draws every child into the same assigned bounds in
  source order so later children paint over earlier children."
  [& args]
  (let [[props children] (elem/parse-args args "stack")]
    (elem/expect-any-children! "stack" children)
    (nodes/make-node StackNode :stack props @{:ui/builtin? true
                                              :constructor stack})))
