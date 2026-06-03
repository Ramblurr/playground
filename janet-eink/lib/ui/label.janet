# Label, some text

(import ./element :as elem)
(import ./nodes :as nodes)

(defn- text-from-values
  [values]
  (if (zero? (length values))
    ""
    (string ;values)))

(defn- label-child-elements
  [_self _ctx _element]
  @[])

(def LabelNode
  (table/setproto @{:child-elements label-child-elements}
                  nodes/TerminalNode))

(defn label
  "Creates a terminal label node.

  Forms:

      [label \"Hello\"]
      [label {:size 24} \"Hello\"]

  Multiple text values are concatenated with `string`; zero values produce an
  empty string."
  [& args]
  (let [[props text-values] (elem/parse-args args "label")]
    (nodes/make-node LabelNode :label props @{:ui/builtin? true
                                              :constructor label
                                              :text-values text-values
                                              :text (text-from-values text-values)})))
