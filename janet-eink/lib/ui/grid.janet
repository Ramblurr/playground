# Row/column grid container node.
#
# Grid lays children out row-major across a fixed column spec list and
# an inferred or explicit row spec list. Track specs are either :hug or
# {:stretch n}; stretched tracks divide leftover space after hug tracks and gaps.

(import ./core :as core)
(import ./element :as elem)
(import ./nodes :as nodes)
(import ./util :as util)


(defn- seq?
  [value]
  (or (array? value) (tuple? value)))

(defn- finite-number?
  [value]
  (and (= :number (type value))
       (= value value)
       (not (= value math/inf))
       (not (= value (- math/inf)))))

(defn- positive-integer?
  [value]
  (and (finite-number? value)
       (> value 0)
       (= value (math/floor value))))

(defn- expect-positive-integer!
  [who value]
  (unless (positive-integer? value)
    (error (string who " expected a positive integer, got " value)))
  value)

(defn- stretch-track?
  [spec]
  (and (util/props? spec) (has-key? spec :stretch)))

(defn- normalize-track-spec
  [who spec]
  (cond
    (= :hug spec)
    :hug

    (stretch-track? spec)
    (let [factor (get spec :stretch)]
      (unless (and (finite-number? factor) (> factor 0))
        (error (string "grid: " who " stretch factor must be a positive number, got " factor)))
      {:stretch factor})

    :else
    (error (string "grid: " who " track spec must be :hug or {:stretch positive-number}, got " spec))))

(defn- repeat-hug
  [count]
  (let [out @[]]
    (var i 0)
    (while (< i count)
      (array/push out :hug)
      (++ i))
    out))

(defn- normalize-track-list
  [who value]
  (cond
    (positive-integer? value)
    (repeat-hug value)

    (seq? value)
    (let [out @[]]
      (each spec value
        (array/push out (normalize-track-spec who spec)))
      (when (= 0 (length out))
        (error (string "grid: " who " must contain at least one track")))
      out)

    :else
    (error (string "grid: " who " must be a positive integer or an array/tuple of track specs, got " value))))

(defn- validate-gap-option!
  [props key]
  (when (has-key? props key)
    (let [value (get props key)]
      (unless (or (nil? value) (= false value) (core/dimension? value))
        (error (string "grid: " key " expected number or function dimension, got " (type value))))))
  props)

(defn- validate-grid-props!
  [props]
  (unless (has-key? props :cols)
    (error "grid: props must include :cols"))
  (normalize-track-list ":cols" (get props :cols))
  (when (has-key? props :rows)
    (let [rows (get props :rows)]
      (when (not (nil? rows))
        (normalize-track-list ":rows" rows))))
  (validate-gap-option! props :gap)
  (validate-gap-option! props :col-gap)
  (validate-gap-option! props :row-gap)
  props)

(defn- prop-value
  [props key]
  (when (util/props? props)
    (get props key nil)))

(defn- child-layout-prop
  [child key]
  (or (prop-value (get child :props nil) key)
      (when-let [element (get child :element nil)]
        (when (tuple? element)
          (prop-value (elem/element-props element) key)))))

(defn- child-col-span-value
  [child]
  (or (child-layout-prop child :col-span)
      (child-layout-prop child :ui/col-span)))

(defn- child-col-span
  [child]
  (let [value (child-col-span-value child)]
    (if (or (nil? value) (= false value))
      1
      (expect-positive-integer! "grid: child :col-span" value))))

(defn- total-child-columns
  [children]
  (var total 0)
  (each child (or children @[])
    (set total (+ total (child-col-span child))))
  total)

(defn- inferred-row-count
  [cols-count children]
  (max 1 (math/ceil (/ (total-child-columns children) cols-count))))

(defn- append-hug-rows!
  [rows target-count]
  (while (< (length rows) target-count)
    (array/push rows :hug))
  rows)

(defn- normalized-cols
  [props]
  (normalize-track-list ":cols" (get props :cols)))

(defn- normalized-rows
  [props cols-count children]
  (let [needed (inferred-row-count cols-count children)
        raw (get props :rows nil)
        rows (if (nil? raw)
               (repeat-hug needed)
               (normalize-track-list ":rows" raw))]
    (append-hug-rows! rows needed)))

(defn- gap-spec
  [props primary]
  (let [specific (get props primary nil)
        fallback (get props :gap nil)]
    (cond
      (and (not (nil? specific)) (not (= false specific))) specific
      (and (not (nil? fallback)) (not (= false fallback))) fallback
      :else 0)))

(defn- resolved-gap
  [ctx props cs primary]
  (nodes/clamp-nonnegative (core/dimension ctx (gap-spec props primary) cs)))

(defn- zero-array
  [count]
  (let [out @[]]
    (var i 0)
    (while (< i count)
      (array/push out 0)
      (++ i))
    out))

(defn- sum-array
  [values]
  (var total 0)
  (each value values
    (set total (+ total value)))
  total)

(defn- gap-total
  [count gap]
  (* gap (max 0 (- count 1))))

(defn- track-stretch
  [spec]
  (when (not (= :hug spec))
    (get spec :stretch)))

(defn- total-stretch
  [specs]
  (var total 0)
  (each spec specs
    (when-let [factor (track-stretch spec)]
      (set total (+ total factor))))
  total)

(defn- count-stretch-tracks
  [specs]
  (var count 0)
  (each spec specs
    (when (track-stretch spec)
      (++ count)))
  count)

(defn- hug-total
  [specs sizes]
  (var total 0)
  (var i 0)
  (while (< i (length specs))
    (when (= :hug (get specs i))
      (set total (+ total (get sizes i))))
    (++ i))
  total)

(defn- allocate-stretch-tracks!
  [specs sizes leftover stretch-total]
  (var assigned-sum 0)
  (var remaining (count-stretch-tracks specs))
  (var i 0)
  (while (< i (length specs))
    (when-let [factor (track-stretch (get specs i))]
      (let [assigned (if (= remaining 1)
                       (- leftover assigned-sum)
                       (math/round (* leftover (/ factor stretch-total))))
            assigned (nodes/clamp-nonnegative assigned)]
        (put sizes i assigned)
        (set assigned-sum (+ assigned-sum assigned))
        (-- remaining)))
    (++ i))
  sizes)

(defn- resolve-track-sizes!
  [specs sizes available gap]
  (let [stretch-total (total-stretch specs)]
    (when (> stretch-total 0)
      (let [leftover (nodes/clamp-nonnegative (- available
                                                  (hug-total specs sizes)
                                                  (gap-total (length specs) gap)))]
        (allocate-stretch-tracks! specs sizes leftover stretch-total))))
  sizes)

(defn- ensure-span-fits!
  [cols-count row col span]
  (when (> span cols-count)
    (error (string "grid: child :col-span " span " exceeds column count " cols-count)))
  (when (> (+ col span) cols-count)
    (error (string "grid: child :col-span " span " at row " row " column " col " exceeds remaining columns")))
  span)

(defn- set-max!
  [values index value]
  (when (> value (get values index))
    (put values index value))
  values)

(defn- measure-hug-tracks!
  [children ctx cs cols rows]
  (let [widths (zero-array (length cols))
        heights (zero-array (length rows))]
    (var row 0)
    (var col 0)
    (each child (or children @[])
      (let [span (child-col-span child)]
        (ensure-span-fits! (length cols) row col span)
        (when (>= row (length rows))
          (error "grid: not enough rows for children"))
        (let [size (nodes/measure child ctx cs)]
          (when (= span 1)
            (set-max! widths col (get size :w)))
          (set-max! heights row (get size :h)))
        (set col (+ col span))
        (when (>= col (length cols))
          (++ row)
          (set col 0))))
    @{:widths widths
      :heights heights}))

(defn- grid-layout
  [self ctx cs]
  (let [props (get self :props @{})
        children (get self :children @[])
        cols (normalized-cols props)
        rows (normalized-rows props (length cols) children)
        col-gap (resolved-gap ctx props cs :col-gap)
        row-gap (resolved-gap ctx props cs :row-gap)
        measured (measure-hug-tracks! children ctx cs cols rows)
        widths (get measured :widths)
        heights (get measured :heights)]
    (resolve-track-sizes! cols widths (get cs :w) col-gap)
    (resolve-track-sizes! rows heights (get cs :h) row-gap)
    @{:cols cols
      :rows rows
      :widths widths
      :heights heights
      :col-gap col-gap
      :row-gap row-gap}))

(defn- layout-size
  [layout]
  (let [widths (get layout :widths)
        heights (get layout :heights)]
    (nodes/make-size (+ (sum-array widths) (gap-total (length widths) (get layout :col-gap)))
                     (+ (sum-array heights) (gap-total (length heights) (get layout :row-gap))))))

(defn- grid-measure
  [self ctx cs]
  (layout-size (grid-layout self ctx cs)))

(defn- track-position
  [origin sizes gap index]
  (var pos origin)
  (var i 0)
  (while (< i index)
    (set pos (+ pos (get sizes i) gap))
    (++ i))
  pos)

(defn- span-size
  [sizes gap start span]
  (var total 0)
  (var i start)
  (while (< i (+ start span))
    (set total (+ total (get sizes i)))
    (++ i))
  (+ total (gap-total span gap)))

(defn- draw-children
  [self ctx bounds layout]
  (let [children (get self :children @[])
        widths (get layout :widths)
        heights (get layout :heights)
        col-gap (get layout :col-gap)
        row-gap (get layout :row-gap)
        cols-count (length widths)]
    (var row 0)
    (var col 0)
    (each child children
      (let [span (child-col-span child)]
        (ensure-span-fits! cols-count row col span)
        (when (>= row (length heights))
          (error "grid: not enough rows for children"))
        (let [x (track-position (get bounds :x) widths col-gap col)
              y (track-position (get bounds :y) heights row-gap row)
              w (span-size widths col-gap col span)
              h (get heights row)]
          (nodes/draw child ctx (nodes/make-bounds x y w h)))
        (set col (+ col span))
        (when (>= col cols-count)
          (++ row)
          (set col 0))))))

(defn- grid-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (let [layout (grid-layout self ctx (nodes/make-size (get bounds :w) (get bounds :h)))]
    (draw-children self ctx bounds layout))
  self)

(def GridNode
  (table/setproto @{:measure grid-measure
                    :draw grid-draw}
                  nodes/ContainerNode))

(defn grid
  "Creates a row-major grid container.

  Forms:
      [grid {:cols 2} child ...]
      [grid {:cols [:hug {:stretch 1} :hug] :rows [:hug {:stretch 1}]} child ...]
      [grid {:cols 3 :gap 8} child ...]
      [grid {:cols 3 :col-gap 16 :row-gap 8} child ...]

  Options:
      :cols    positive-integer | track-spec array/tuple - required columns
      :rows    positive-integer | track-spec array/tuple - optional rows
      :gap     number | function - fallback for both row and column gaps
      :col-gap number | function - column gap override
      :row-gap number | function - row gap override

  Track specs are :hug or {:stretch positive-number}. Missing rows are inferred
  from the children and appended as :hug rows when needed. Children are placed
  row-major and fill their cell bounds. A child may set :col-span (or
  :ui/col-span) in its element props to span multiple columns."
  [& args]
  (let [props (elem/require-props! "grid" args)
        [_parsed-props children] (elem/parse-args args "grid")]
    (validate-grid-props! props)
    (elem/expect-any-children! "grid" children)
    (nodes/make-node GridNode :grid props @{:ui/builtin? true
                                            :constructor grid})))
