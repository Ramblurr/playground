# Explicit grow wrapper node for row/column leftover space.

(import ./element :as elem)
(import ./nodes :as nodes)


(defn- grow-measure
  [self ctx cs]
  (nodes/measure (get self :child nil) ctx cs))

(defn- grow-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (when-let [child (get self :child nil)]
    (nodes/draw child ctx bounds))
  self)

(defn- grow-shape-error
  []
  (error "grow: expected [grow child] or [grow positive-factor child]"))

(defn- parse-grow-args
  [args]
  (case (length args)
    1 [1 (get args 0)]
    2 [(elem/expect-positive-number! "grow factor" (get args 0)) (get args 1)]
    (grow-shape-error)))

(defn- grow-child-elements
  [_self _ctx element]
  (let [args (elem/values->array element 1)
        [_factor child] (parse-grow-args args)]
    @[child]))

(def GrowNode
  (table/setproto @{:child-elements grow-child-elements
                    :measure grow-measure
                    :draw grow-draw}
                  nodes/WrapperNode))

(defn grow
  "Creates an explicit grow wrapper.

  Forms:
      [grow child]       # factor 1
      [grow 2 child]     # factor 2

  Outside row/column, grow delegates measure and draw to its child. Inside
  row/column, the container reads the positive factor and assigns a proportional
  share of leftover main-axis space before grow delegates drawing to its child."
  [& args]
  (let [[factor child] (parse-grow-args args)]
    (elem/expect-one-child! "grow" @[child])
    (nodes/make-node GrowNode :grow @{} @{:ui/builtin? true
                                          :constructor grow
                                          :factor factor})))
