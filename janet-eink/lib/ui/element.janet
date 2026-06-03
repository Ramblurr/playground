# Element parsing and child normalization helpers.
#
# UI source forms are ordinary Janet tuple literals, e.g.
#
#   [ui/row {:gap 8} [ui/label "left"] [ui/label "right"]]
#
# Slot 0 is the callable head. Slot 1 is props only when it is a table or
# struct. Remaining slots are children/arguments. Arrays in child positions are
# child groups and are flattened; tuple values remain element markup.

(import ./util :as util)


(defn element?
  "Returns true when `x` is tuple markup with a head slot."
  [x]
  (and (tuple? x) (> (length x) 0)))

(defn omitted?
  "Returns true for child values that should be omitted from the UI tree."
  [x]
  (or (nil? x) (= false x)))

(defn child-group?
  "Returns true when `x` is a recursive child group.

  Otter UI markup uses tuples. Mutable arrays in child positions are therefore
  groups to flatten, while tuples are preserved as single element values."
  [x]
  (array? x))

(defn callable-head?
  "Returns true when `x` is a valid callable element head for this slice."
  [x]
  (function? x))


(defn- assert-indexed-list!
  [xs who]
  (unless (or (array? xs) (tuple? xs) (nil? xs))
    (error (string who ": expected an array or tuple of values, got " (util/type-name xs))))
  xs)

(defn- slice->array
  [xs start]
  (def out @[])
  (when xs
    (var i start)
    (while (< i (length xs))
      (array/push out (get xs i))
      (++ i)))
  out)

(defn values->array
  "Copies an array/tuple/nil into a mutable array.

  `start` is an optional zero-based offset."
  [xs &opt start]
  (assert-indexed-list! xs "values->array")
  (slice->array xs (or start 0)))

(defn props-supplied?
  "Returns true when the first argument slot is a props table/struct."
  [args]
  (assert-indexed-list! args "props-supplied?")
  (and args (> (length args) 0) (util/props? (get args 0))))

(defn parse-args
  "Parses post-head constructor args.

  Returns `[props children]`, where props defaults to an empty mutable table and
  children is a mutable array of the remaining raw child/argument values."
  [args &opt who]
  (def label (or who "parse-args"))
  (assert-indexed-list! args label)
  (if (props-supplied? args)
    [(get args 0) (slice->array args 1)]
    [@{} (slice->array args 0)]))

(defn parse-element
  "Parses tuple element markup into `[head props children]`.

  `nil` and `false` return nil so callers can omit them. Non-tuple values raise
  clear errors; strings should be autoconverted before calling this function."
  [el]
  (cond
    (omitted? el)
    nil

    (not (tuple? el))
    (error (string "parse-element: expected tuple element markup, got " (util/type-name el)))

    (= 0 (length el))
    (error "parse-element: expected tuple element markup with a head, got empty tuple")

    :else
    (let [head (get el 0)
          [props children] (parse-args (slice->array el 1) "parse-element")]
      [head props children])))

(defn element-head
  "Returns the head from tuple element markup."
  [el]
  (get (parse-element el) 0))

(defn element-props
  "Returns the parsed props from tuple element markup."
  [el]
  (get (parse-element el) 1))

(defn element-children
  "Returns parsed raw children from tuple element markup as a mutable array."
  [el]
  (get (parse-element el) 2))

(defn parse-props
  "Returns the explicit props map from `el`, or nil when no props were supplied."
  [el]
  (when-let [parsed (parse-element el)]
    (let [raw-second (get el 1 nil)]
      (when (util/props? raw-second)
        (get parsed 1)))))

(defn- identity-convert
  [x]
  x)

(defn- normalize-child-into!
  [out child convert]
  (cond
    (omitted? child)
    nil

    (child-group? child)
    (each item child
      (normalize-child-into! out item convert))

    :else
    (let [converted (convert child)]
      (cond
        (omitted? converted)
        nil

        (child-group? converted)
        (each item converted
          (normalize-child-into! out item convert))

        :else
        (array/push out converted)))))

(defn normalize-children
  "Omits nil/false children and recursively flattens array child groups.

  Tuples are preserved as element markup. `convert`, when supplied, is called for
  each non-array leaf after omission/group flattening. Reconcile can use it to
  autoconvert bare strings into `[label text]` markup without making this module
  depend on concrete widgets."
  [children &opt convert]
  (assert-indexed-list! children "normalize-children")
  (let [out @[]
        convert-leaf (or convert identity-convert)]
    (each child (or children @[])
      (normalize-child-into! out child convert-leaf))
    out))

(defn flatten-children
  "Alias for `normalize-children` without leaf conversion."
  [children]
  (normalize-children children))

(defn string->label-markup
  "Converts a string to `[label-head string]` markup.

  Other values are returned unchanged. This helper keeps concrete label imports
  out of element parsing; pass the actual `ui/label` function as `label-head`."
  [label-head value]
  (if (string? value)
    [label-head value]
    value))

(defn normalize-child-elements
  "Normalizes children and autoconverts strings to label markup.

  `label-head` must be the label constructor function to place in slot 0 of the
  generated label element."
  [children label-head]
  (normalize-children children (fn [child] (string->label-markup label-head child))))

(defn assert-callable-head!
  "Raises unless `head` is callable; returns `head` otherwise."
  [head &opt element]
  (unless (callable-head? head)
    (error (string "element head must be callable, got " (util/type-name head)
                   (if element (string " in " element) ""))))
  head)

(defn assert-element!
  "Raises unless `value` is tuple element markup with a callable head; returns `value`."
  [value &opt who]
  (unless (element? value)
    (error (string (or who "element") ": expected tuple element markup with a callable head, got "
                   (util/type-name value))))
  (let [head (element-head value)]
    (unless (callable-head? head)
      (error (string (or who "element") ": expected callable head, got " (util/type-name head)))))
  value)

(defn require-props!
  "Raises unless constructor `args` started with a props table/struct.

  Returns the parsed props. Useful for built-ins such as `rect` whose props are
  required in the first slice."
  [who args]
  (unless (props-supplied? args)
    (error (string who ": expected props table as the first argument")))
  (get args 0))

(defn child-count-error
  [who expected children]
  (error (string who ": expected " expected ", got " (length children) " child value(s)")))

(defn expect-no-children!
  "Normalizes `children` and raises unless none remain."
  [who children]
  (let [normalized (normalize-children children)]
    (unless (= 0 (length normalized))
      (child-count-error who "no children" normalized))
    normalized))

(defn expect-one-child!
  "Normalizes `children` and returns the single child, or raises."
  [who children]
  (let [normalized (normalize-children children)]
    (unless (= 1 (length normalized))
      (child-count-error who "exactly one child" normalized))
    (get normalized 0)))

(defn expect-zero-or-one-child!
  "Normalizes `children` and returns nil or the single child, or raises." 
  [who children]
  (let [normalized (normalize-children children)]
    (when (> (length normalized) 1)
      (child-count-error who "zero or one child" normalized))
    (get normalized 0 nil)))

(defn expect-any-children!
  "Normalizes `children` and returns the resulting array.

  This exists for containers where zero or more children are valid but nil/false
  omission and array-group flattening should still happen at construction time."
  [_who children]
  (normalize-children children))

(defn positive-number?
  "Returns true when `x` is a number greater than zero."
  [x]
  (and (= :number (type x)) (> x 0)))

(defn expect-positive-number!
  "Raises unless `x` is a positive number; returns `x` otherwise."
  [who x]
  (unless (positive-number? x)
    (error (string who ": expected a positive number, got " (util/type-name x))))
  x)
