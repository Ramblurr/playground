# Descendant context override wrapper node.

(import ./element :as elem)
(import ./nodes :as nodes)


(defn- merged-context
  [self ctx]
  (merge ctx (get self :props @{})))

(defn- with-context-measure
  [self ctx cs]
  (nodes/measure (get self :child nil) (merged-context self ctx) cs))

(defn- with-context-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (when-let [child (get self :child nil)]
    (nodes/draw child (merged-context self ctx) bounds))
  self)

(def WithContextNode
  (table/setproto @{:measure with-context-measure
                    :draw with-context-draw}
                  nodes/WrapperNode))

(defn with-context
  "Creates a wrapper that merges context overrides for descendants.

  Forms:
      [with-context {:paint \"0\" :font-size 20} child]

  The overrides table is merged into the inherited context for child measurement
  and drawing. Descendant props still override context through each concrete node's
  normal option resolution."
  [& args]
  (let [props (elem/require-props! "with-context" args)
        [_parsed-props children] (elem/parse-args args "with-context")]
    (elem/expect-one-child! "with-context" children)
    (nodes/make-node WithContextNode :with-context props @{:ui/builtin? true
                                                           :constructor with-context})))
