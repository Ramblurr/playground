(ns ol.membrane.paragraph
  (:require
   [membrane.ui :as ui]))

(defrecord Paragraph [text font width align]
  ui/IOrigin
  (-origin [_]
    [0 0]))

(def ^:private paragraph-alignments
  #{:left})

(defn- normalize-align
  [align]
  (let [align (or align :left)]
    (when-not (contains? paragraph-alignments align)
      (throw (ex-info "unsupported paragraph alignment"
                      {:align     align
                       :supported paragraph-alignments})))
    align))

(defn paragraph
  "Creates a fixed-width paragraph text block.

  A paragraph is backend-neutral. Backends measure and draw it with real
  paragraph/line layout rather than one `label` per word.

  Options:

  | key      | description |
  |----------|-------------|
  | `:align` | Paragraph alignment. Currently supports `:left` (default). |"
  ([text width]
   (paragraph text ui/default-font width nil))
  ([text font width]
   (paragraph text font width nil))
  ([text font width {:keys [align]}]
   (->Paragraph (str text)
                (or font ui/default-font)
                (double width)
                (normalize-align align))))
