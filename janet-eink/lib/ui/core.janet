# Shared UI helpers
#
# Public widget dimensions are logical units (DIP). Node measure/draw methods work
# in device pixels, so helpers here resolve logical values through `ctx :scale`.

(import ./util :as util)


(defn scale
  "Returns the UI scale from `ctx`, defaulting to 1."
  [ctx]
  (if (util/props? ctx)
    (get ctx :scale 1)
    1))

(defn scaled
  "Converts logical dimension `x` to device pixels using ceil(x * scale)."
  [ctx x]
  (math/ceil (* x (scale ctx))))

(defn descaled
  "Converts device-pixel dimension `x` back to logical units, preserving nil."
  [ctx x]
  (when x
    (/ x (scale ctx))))

(defn dimension?
  "Returns true when `x` is a numeric or function dimension."
  [x]
  (or (= :number (type x)) (function? x)))

(defn- constraint-value
  [cs primary fallback]
  (if (util/props? cs)
    (or (get cs primary nil) (get cs fallback nil))
    nil))

(defn- logical-constraints
  [ctx cs]
  (let [w (constraint-value cs :width :w)
        h (constraint-value cs :height :h)
        logical-w (descaled ctx w)
        logical-h (descaled ctx h)
        s (scale ctx)]
    {:w logical-w
     :h logical-h
     :width logical-w
     :height logical-h
     :scale s}))

(defn dimension
  "Resolves numeric/function dimension `size` into device pixels with round(x * scale).

  Function dimensions receive logical constraints with `:w`/`:h`,
  `:width`/`:height`, and `:scale` keys."
  [ctx size cs]
  (cond
    (= :number (type size))
    (math/round (* size (scale ctx)))

    (function? size)
    (math/round (* (size (logical-constraints ctx cs)) (scale ctx)))

    :else
    (error (string "dimension: expected number or function, got " (util/type-name size)))))
