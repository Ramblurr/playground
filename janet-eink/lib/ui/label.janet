# Shaped terminal text label.

(import ../skia :as skia)
(import ./core :as core)
(import ./element :as elem)
(import ./nodes :as nodes)

(defn- text-from-values
  [values]
  (if (zero? (length values))
    ""
    (string ;values)))

(defn- option
  [props ctx key default]
  (get props key (get ctx key default)))

(defn- feature-seq?
  [value]
  (or (= :array (type value)) (= :tuple (type value))))

(defn- push-features!
  [out value]
  (cond
    (nil? value) nil
    (string? value) (array/push out value)
    (feature-seq? value) (each feature value
                           (unless (string? feature)
                             (error (string "label: font-features expects strings, got " (type feature))))
                           (array/push out feature))
    :else (error (string "label: font-features expects a string or array/tuple of strings, got " (type value)))))

(defn- resolve-font-features
  [props ctx]
  (def features @[])
  (push-features! features (get props :font-features nil))
  (push-features! features (get ctx :font-features nil))
  (if (zero? (length features)) nil features))

(defn- resolve-font-options
  [props ctx]
  (let [scale (core/scale ctx)
        font-size (option props ctx :font-size 16)
        scaled-font-size (core/scaled ctx font-size)
        features (resolve-font-features props ctx)]
    @{:font-family (option props ctx :font-family "Noto Sans")
      :font-size scaled-font-size
      :font-weight (option props ctx :font-weight 400)
      :font-width (option props ctx :font-width :normal)
      :font-slant (option props ctx :font-slant :upright)
      :font-features features
      :scale scale}))

(defn- shape-key
  [text font-options]
  {:text text
   :font-family (get font-options :font-family)
   :font-size (get font-options :font-size)
   :font-weight (get font-options :font-weight)
   :font-width (get font-options :font-width)
   :font-slant (get font-options :font-slant)
   :font-features (get font-options :font-features)
   :scale (get font-options :scale)})

(defn- ensure-shaped!
  [self ctx]
  (let [canvas (get ctx :canvas nil)
        props (get self :props @{})
        text (text-from-values (get self :text-values @[]))
        font-options (resolve-font-options props ctx)
        next-key (shape-key text font-options)]
    (unless canvas
      (error "label: measure/draw requires ctx :canvas"))
    (put self :text text)
    (when (or (nil? (get self :text-line nil))
              (not (deep= next-key (get self :shape-key nil))))
      (def line (skia/shape-text canvas text font-options))
      (def metrics (skia/text-line-metrics line))
      (put self :shape-key next-key)
      (put self :font-features (get font-options :font-features))
      (put self :text-line line)
      (put self :size (nodes/make-size (get metrics :width) (get metrics :height))))
    (or (get self :size nil) (nodes/zero-size))))

(defn- label-measure
  [self ctx _cs]
  (ensure-shaped! self ctx))

(defn- label-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (let [size (ensure-shaped! self ctx)
        line (get self :text-line nil)
        text (get self :text "")
        paint (option (get self :props @{}) ctx :paint skia/black)]
    (when (and line (> (length text) 0) (> (get size :w) 0) (> (get size :h) 0))
      (skia/draw-text-line (get ctx :canvas) line (get bounds :x) (get bounds :y) {:gray paint})))
  self)

(defn- label-unmount
  [self]
  (put self :shape-key nil)
  (put self :font-features nil)
  (put self :text-line nil)
  (put self :size nil)
  ((get nodes/TerminalNode :unmount) self))

(defn- label-child-elements
  [_self _ctx _element]
  @[])

(def LabelNode
  (table/setproto @{:child-elements label-child-elements
                    :measure label-measure
                    :draw label-draw
                    :unmount label-unmount}
                  nodes/TerminalNode))

(defn label
  "Creates a shaped terminal label node.

  Forms:
      [label \"Hello\"]
      [label {:font-size 24 :font-family \"Noto Sans\" :font-weight 700} \"Hello\"]
      [label {:font-features [\"tnum\" \"zero\"]} \"123\"]

  Multiple text values are concatenated with `string`; zero values produce an
  empty string."
  [& args]
  (let [[props text-values] (elem/parse-args args "label")]
    (nodes/make-node LabelNode :label props @{:ui/builtin? true
                                              :constructor label
                                              :retain-fields [:shape-key :font-features :text-line :size]
                                              :text-values text-values
                                              :text (text-from-values text-values)
                                              :shape-key nil
                                              :font-features nil
                                              :text-line nil
                                              :size nil})))
