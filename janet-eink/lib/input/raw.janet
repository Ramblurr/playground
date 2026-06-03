(import ./constants :as constants)

(def default-time @{:sec 0 :usec 0})

(defn- dict?
  [value]
  (or (= :table (type value)) (= :struct (type value))))

(defn- number-value?
  [value]
  (= :number (type value)))

(defn- copy-table
  [source]
  (let [out @{}]
    (when (dict? source)
      (eachp [key value] source
        (put out key value)))
    out))

(defn source
  [kind &opt opts]
  (let [out @{:kind kind}]
    (when opts
      (unless (dict? opts)
        (error "input source options must be a table or struct"))
      (eachp [key value] opts
        (put out key value)))
    out))

(defn- maybe-lookup
  [f value]
  (let [result (protect (f value))]
    (if (get result 0)
      (get result 1)
      nil)))

(defn- resolve-key-code
  [code]
  (if (number-value? code)
    code
    (or (maybe-lookup constants/key-code code)
        (maybe-lookup constants/fake-system-code code)
        (error (string "unknown key or fake/system code: " code)))))

(defn- resolve-code
  [type-code code]
  (if (number-value? code)
    code
    (case (constants/event-type-name type-code)
      :ev-syn (constants/syn-code code)
      :ev-abs (constants/abs-code code)
      :ev-key (resolve-key-code code)
      code)))

(defn make
  [type code value &opt opts]
  (let [options (or opts @{})]
    (unless (dict? options)
      (error "raw input options must be a table or struct"))
    (let [type-code (constants/event-type-code type)]
      @{:type type-code
        :code (resolve-code type-code code)
        :value value
        :time (copy-table (get options :time default-time))
        :source (get options :source nil)})))

(defn raw-record?
  [record]
  (and (dict? record)
       (number-value? (get record :type nil))
       (number-value? (get record :code nil))
       (number-value? (get record :value nil))
       (dict? (get record :time nil))))

(defn- source-label
  [source]
  (if (dict? source)
    (let [kind (get source :kind nil)
          path (get source :path nil)
          name (get source :name nil)
          control (get source :control nil)]
      (cond
        path (string kind "[" path (if name (string " " name) "") "]")
        control (string kind "[" control "]")
        :else (string kind)))
    "unknown-source"))

(defn- code-name
  [type-code code]
  (case (constants/event-type-name type-code)
    :ev-syn (or (constants/syn-name code) code)
    :ev-abs (or (constants/abs-name code) code)
    :ev-key (or (constants/key-name code) (constants/fake-system-name code) code)
    code))

(defn- code-label
  [type-code code]
  (case (constants/event-type-name type-code)
    :ev-syn (constants/syn-label code)
    :ev-abs (constants/abs-label code)
    :ev-key (if (constants/fake-system-name code)
              (constants/fake-system-label code)
              (constants/key-label code))
    (string code)))

(defn- timestamp-label
  [time]
  (string/format "%d.%06d" (get time :sec 0) (get time :usec 0)))

(defn format-record
  [record]
  (unless (raw-record? record)
    (error "format-record expects a raw input record"))
  (let [type-code (get record :type)
        code (get record :code)]
    (string (source-label (get record :source nil))
            " " (constants/event-type-label type-code)
            " " (code-label type-code code)
            "(" (code-name type-code code) "/" code ")"
            " value=" (get record :value)
            " time=" (timestamp-label (get record :time)))))
