# Paint specs and normalized paint data for Otter drawing.

(defn- dict?
  [value]
  (or (= :table (type value)) (= :struct (type value))))

(defn- seq?
  [value]
  (or (= :array (type value)) (= :tuple (type value))))

(defn- finite?
  [value]
  (and (= :number (type value))
       (= value value)
       (not (= value math/inf))
       (not (= value (- math/inf)))))

(defn- integer-number?
  [value]
  (and (finite? value)
       (= value (math/floor value))))

(defn- byte?
  [value]
  (and (integer-number? value)
       (>= value 0)
       (<= value 255)))

(defn- require-byte
  [value label]
  (unless (byte? value)
    (error (string label " must be a byte in 0..255, got " value)))
  value)

(defn- unit?
  [value]
  (and (finite? value) (>= value 0) (<= value 1)))

(defn- require-unit
  [value label]
  (unless (unit? value)
    (error (string label " must be in 0.0..1.0, got " value)))
  value)

(defn- clamp-unit
  [value]
  (cond
    (< value 0) 0
    (> value 1) 1
    :else value))

(def- zero-char (get "0" 0))
(def- nine-char (get "9" 0))
(def- upper-a-char (get "A" 0))
(def- upper-f-char (get "F" 0))
(def- lower-a-char (get "a" 0))
(def- lower-f-char (get "f" 0))

(defn- hex-nibble
  [ch]
  (cond
    (and (>= ch zero-char) (<= ch nine-char)) (- ch zero-char)
    (and (>= ch upper-a-char) (<= ch upper-f-char)) (+ 10 (- ch upper-a-char))
    (and (>= ch lower-a-char) (<= ch lower-f-char)) (+ 10 (- ch lower-a-char))
    :else (error (string "invalid hex digit byte: " ch))))

(defn- hex-byte-at
  [s i]
  (+ (* 16 (hex-nibble (get s i)))
     (hex-nibble (get s (+ i 1)))))

(defn- hex-shorthand-byte-at
  [s i]
  (let [n (hex-nibble (get s i))]
    (+ (* 16 n) n)))

(defn- byte->unit
  [value]
  (/ value 255))

(defn- color-map
  [model r g b a]
  @{:otter/color? true
    :model model
    :r r
    :g g
    :b b
    :a a})

(defn- gray-color
  [gray alpha]
  (color-map :gray8 (byte->unit gray) (byte->unit gray) (byte->unit gray) (byte->unit alpha)))

(defn- parse-gray-string
  [s]
  (case (length s)
    1 (gray-color (hex-shorthand-byte-at s 0) 255)
    2 (gray-color (hex-byte-at s 0) 255)
    4 (gray-color (hex-byte-at s 0) (hex-byte-at s 2))))

(defn- parse-rgb-string
  [s]
  (case (length s)
    3 (color-map :srgb
                 (byte->unit (hex-shorthand-byte-at s 0))
                 (byte->unit (hex-shorthand-byte-at s 1))
                 (byte->unit (hex-shorthand-byte-at s 2))
                 1)
    6 (color-map :srgb
                 (byte->unit (hex-byte-at s 0))
                 (byte->unit (hex-byte-at s 2))
                 (byte->unit (hex-byte-at s 4))
                 1)
    8 (color-map :srgb
                 (byte->unit (hex-byte-at s 0))
                 (byte->unit (hex-byte-at s 2))
                 (byte->unit (hex-byte-at s 4))
                 (byte->unit (hex-byte-at s 6)))))

(defn- parse-color-string
  [s]
  (case (length s)
    1 (parse-gray-string s)
    2 (parse-gray-string s)
    3 (parse-rgb-string s)
    4 (parse-gray-string s)
    6 (parse-rgb-string s)
    8 (parse-rgb-string s)
    (error (string "color string must have length 1, 2, 3, 4, 6, or 8 hex digits, got " (length s)))))

(defn- linear->srgb
  [value]
  (let [x (clamp-unit value)]
    (if (<= x 0.0031308)
      (* 12.92 x)
      (- (* 1.055 (math/pow x (/ 1 2.4))) 0.055))))

(defn- oklch->srgb
  [l c h]
  (let [radians (* h (/ math/pi 180))
        a (* c (math/cos radians))
        b (* c (math/sin radians))
        lp (+ l (* 0.3963377774 a) (* 0.2158037573 b))
        mp (- l (* 0.1055613458 a) (* 0.0638541728 b))
        sp (- l (* 0.0894841775 a) (* 1.2914855480 b))
        l3 (* lp lp lp)
        m3 (* mp mp mp)
        s3 (* sp sp sp)]
    @[(linear->srgb (+ (* 4.0767416621 l3) (* -3.3077115913 m3) (* 0.2309699292 s3)))
      (linear->srgb (+ (* -1.2684380046 l3) (* 2.6097574011 m3) (* -0.3413193965 s3)))
      (linear->srgb (+ (* -0.0041960863 l3) (* -0.7034186147 m3) (* 1.7076147010 s3)))]))

(defn- vector-color
  [spec opts]
  (unless (seq? spec)
    (error "internal error: vector-color expected an indexed color spec"))
  (unless (or (= 3 (length spec)) (= 4 (length spec)))
    (error "color vectors must have 3 or 4 channels"))
  (let [model (get opts :model nil)
        alpha (if (= 4 (length spec)) (get spec 3) 1)]
    (unless model
      (error "color vectors require an explicit :model"))
    (require-unit alpha "alpha channel")
    (case model
      :srgb
      (let [r (require-unit (get spec 0) "red channel")
            g (require-unit (get spec 1) "green channel")
            b (require-unit (get spec 2) "blue channel")]
        (color-map :srgb r g b alpha))

      :oklch
      (let [l (require-unit (get spec 0) "oklch lightness")
            c (get spec 1)
            h (get spec 2)]
        (unless (and (finite? c) (>= c 0))
          (error (string "oklch chroma must be a non-negative finite number, got " c)))
        (unless (finite? h)
          (error (string "oklch hue must be finite, got " h)))
        (let [rgb (oklch->srgb l c h)]
          (color-map :oklch (get rgb 0) (get rgb 1) (get rgb 2) alpha)))

      (error (string "unsupported color model: " model)))))

(defn color
  "Normalize a color spec to unpremultiplied sRGB float channels."
  [spec &opt opts]
  (let [options (or opts @{})]
    (cond
      (string? spec) (parse-color-string spec)
      (seq? spec) (vector-color spec options)
      :else (error (string "unsupported color spec; expected string or explicit-model vector, got " (type spec))))))

(defn- color-field-key
  [spec]
  (var key nil)
  (var count 0)
  (each candidate [:fill :fill-gray :stroke :stroke-gray]
    (unless (nil? (get spec candidate nil))
      (set key candidate)
      (++ count)))
  (unless (= count 1)
    (error (if (= count 0)
             "paint map requires exactly one of :fill, :fill-gray, :stroke, or :stroke-gray"
             "paint map must not contain more than one color field")))
  key)

(defn- style-for-key
  [key]
  (case key
    :fill :fill
    :fill-gray :fill
    :stroke :stroke
    :stroke-gray :stroke))

(defn- color-for-map
  [spec key]
  (case key
    :fill (color (get spec :fill) {:model (get spec :model nil)})
    :stroke (color (get spec :stroke) {:model (get spec :model nil)})
    :fill-gray (gray-color (require-byte (get spec :fill-gray) ":fill-gray")
                           (require-byte (get spec :alpha 255) ":alpha"))
    :stroke-gray (gray-color (require-byte (get spec :stroke-gray) ":stroke-gray")
                             (require-byte (get spec :alpha 255) ":alpha"))))

(defn- boolean-option
  [spec key default]
  (let [value (get spec key nil)]
    (if (nil? value) default (not (not value)))))

(defn- ctx-scale
  [ctx]
  (if (dict? ctx) (get ctx :scale 1) 1))

(defn- positive-finite?
  [value]
  (and (finite? value) (> value 0)))

(defn- scaled-width
  [spec ctx]
  (let [width (get spec :width 1)
        scale (ctx-scale ctx)]
    (unless (positive-finite? width)
      (error (string ":width must be positive, got " width)))
    (unless (positive-finite? scale)
      (error (string "ctx :scale must be positive, got " scale)))
    (math/ceil (* width scale))))

(defn- checked-cap
  [value]
  (case value
    nil :butt
    :butt :butt
    :round :round
    :square :square
    (error (string ":cap must be :butt, :round, or :square, got " value))))

(defn- checked-join
  [value]
  (case value
    nil :miter
    :miter :miter
    :round :round
    :bevel :bevel
    (error (string ":join must be :miter, :round, or :bevel, got " value))))

(defn- checked-miter
  [value]
  (unless (positive-finite? value)
    (error (string ":miter must be positive, got " value)))
  value)

(defn- paint-map
  [spec ctx]
  (let [key (color-field-key spec)
        style (style-for-key key)
        c (color-for-map spec key)
        p @{:otter/paint? true
            :style style
            :r (get c :r)
            :g (get c :g)
            :b (get c :b)
            :a (get c :a)
            :anti-alias? (boolean-option spec :anti-alias? true)
            :skia-dither? (boolean-option spec :skia-dither? false)}]
    (when (= style :stroke)
      (put p :width (scaled-width spec ctx))
      (put p :cap (checked-cap (get spec :cap nil)))
      (put p :join (checked-join (get spec :join nil)))
      (put p :miter (checked-miter (get spec :miter 4))))
    p))

(defn- fill-paint-from-color
  [spec]
  (let [c (color spec)]
    @{:otter/paint? true
      :style :fill
      :r (get c :r)
      :g (get c :g)
      :b (get c :b)
      :a (get c :a)
      :anti-alias? true
      :skia-dither? false}))

(defn- one-paint
  [spec ctx]
  (cond
    (nil? spec) nil
    (string? spec) (fill-paint-from-color spec)
    (dict? spec) (paint-map spec ctx)
    :else (error (string "unsupported paint spec; expected nil, string, or map, got " (type spec)))))

(defn paints
  "Normalize any paint spec to an array of paint maps."
  [spec ctx]
  (let [out @[]]
    (cond
      (nil? spec) out
      (seq? spec)
      (each item spec
        (let [normalized (if (seq? item) (paints item ctx) (one-paint item ctx))]
          (cond
            (nil? normalized) nil
            (seq? normalized) (each nested normalized (array/push out nested))
            :else (array/push out normalized))))
      :else
      (let [normalized (one-paint spec ctx)]
        (when normalized (array/push out normalized))))
    out))

(defn paint
  "Normalize one paint spec to a paint map, paint array, or nil."
  [spec ctx]
  (if (seq? spec)
    (paints spec ctx)
    (one-paint spec ctx)))

(defmacro with-paint
  "Bind normalized paint specs in ctx, then evaluate body."
  [ctx bindings & body]
  (let [c (gensym)
        new-ctx (gensym)]
    ~(let [,c ,ctx
           ,new-ctx (merge ,c @{})]
       ,;(map (fn [binding]
                (let [name (get binding 0)
                      spec (get binding 1)]
                  ~(put ,new-ctx ,name (paint/paints ,spec ,c))))
              bindings)
       ,;body)))
