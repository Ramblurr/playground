(import ./paint :as paint)
(import ./device :as device)

(defn- native-fn
  [name]
  (device/native-fn (device/current) name))

(defn- split-device-args
  [args]
  (if (and (> (length args) 0) (device/device? (get args 0)))
    [(get args 0) (array/slice args 1)]
    [(device/current) args]))

(def- module-file (os/realpath (dyn :current-file)))

(defn- dirname
  [path]
  (var i (- (length path) 1))
  (while (and (>= i 0) (not= (get path i) (chr "/")))
    (-- i))
  (if (< i 0) "." (string/slice path 0 i)))

(defn- source-root
  []
  (dirname (dirname module-file)))

(defn- install-root
  []
  (dirname (source-root)))

(defn- file?
  [path]
  (= :file (os/stat path :mode)))

(defn- font-dir?
  [path]
  (and path
       (= :directory (os/stat path :mode))
       (file? (string path "/NotoSans.ttf"))
       (file? (string path "/NotoSerif.ttf"))))

(defn default-font-dir
  []
  (def env (os/getenv "OTTER_FONT_DIR"))
  (if (font-dir? env)
    env
    (do
      (def source-bundled (string (source-root) "/share/otter/fonts"))
      (def install-bundled (string (install-root) "/share/otter/fonts"))
      (cond
        (font-dir? source-bundled) source-bundled
        (font-dir? install-bundled) install-bundled
        :else nil))))

(defn- font-dir-value
  [opts]
  (or (get opts :font-dir) (default-font-dir)))


(defn- family-name
  [value]
  (case value
    :sans "Noto Sans"
    :serif "Noto Serif"
    :default ""
    nil "Noto Sans"
    value))

(defn- weight-value
  [value]
  (case value
    :regular 400
    :bold 700
    nil 400
    value))

(defn- font-size-value
  [opts]
  (get opts :font-size 16))

(defn- font-weight-value
  [opts]
  (weight-value (get opts :font-weight nil)))

(defn- font-width-value
  [opts]
  (case (get opts :font-width :normal)
    :ultra-condensed 1
    :extra-condensed 2
    :condensed 3
    :semi-condensed 4
    :normal 5
    :semi-expanded 6
    :expanded 7
    :extra-expanded 8
    :ultra-expanded 9
    nil 5
    (get opts :font-width)))

(defn- font-slant-value
  [opts]
  (case (get opts :font-slant :upright)
    :upright 0
    :italic 1
    :oblique 2
    nil 0
    (get opts :font-slant)))

(defn- font-features-string
  [opts]
  (def value (get opts :font-features nil))
  (cond
    (nil? value) ""
    (string? value) value
    (or (= :array (type value)) (= :tuple (type value)))
    (do
      (def parts @[])
      (each feature value
        (unless (string? feature)
          (error (string "font-features expects strings, got " (type feature))))
        (array/push parts feature))
      (string/join parts " "))
    :else
    (error (string "font-features expects a string or array/tuple of strings, got " (type value)))))


(defn screen-size
  [&opt dev]
  (device/screen-size (or dev (device/current))))

(defn- create-native
  [dev width height pixel-format font-dir default-family]
  (device/set-current! dev)
  (if font-dir
    ((device/native-fn dev 'create) width height pixel-format font-dir default-family)
    ((device/native-fn dev 'create) width height pixel-format)))

(defn create
  [& args]
  (let [[dev create-args] (split-device-args args)]
    (case (length create-args)
      0 (let [size (screen-size dev)]
          (create-native dev (get size :width) (get size :height) (get size :pixel-format :gray8) (default-font-dir) "Noto Sans"))
      1 (let [opts (get create-args 0)]
          (unless (or (= :table (type opts)) (= :struct (type opts)))
            (error "skia/create with one argument expects an options table"))
          (let [size (screen-size dev)]
            (create-native dev (get opts :width)
                           (get opts :height)
                           (get opts :pixel-format (get size :pixel-format :gray8))
                           (font-dir-value opts)
                           (family-name (get opts :font :sans)))))
      2 (create-native dev (get create-args 0) (get create-args 1) :gray8 (default-font-dir) "Noto Sans")
      (error "skia/create expects an optional device plus zero args, width/height, or an options table"))))

(defn- dict?
  [value]
  (or (= :table (type value)) (= :struct (type value))))

(defn- ensure-draw-options
  [name opts]
  (unless (dict? opts)
    (error (string name " expects an options table with :paint")))
  (unless (has-key? opts :paint)
    (error (string name " options require :paint")))
  opts)


(defn- quantize-gray-levels
  [name opts]
  (def levels (get opts :quantize-gray-levels 0))
  (if (nil? levels) 0 levels))

(defn- dither-mode
  [name opts auto-mode]
  (def mode (get opts :dither :none))
  (case mode
    nil :none
    :none :none
    :ordered :ordered
    :auto auto-mode
    (error (string name " :dither must be :none, :ordered, or :auto"))))

(defn- conversion-options
  [name opts auto-mode]
  (def options (or opts @{}))
  (unless (dict? options)
    (error (string name " expects an options table")))
  @{:quantize-gray-levels (quantize-gray-levels name options)
    :dither (dither-mode name options auto-mode)})
(defn- draw-paints
  [name opts]
  (let [options (ensure-draw-options name opts)]
    (paint/paints (get options :paint) options)))

(defn- require-fill-paint
  [name p]
  (unless (= :fill (get p :style))
    (error (string name " requires a fill paint")))
  p)

(defn- require-stroke-paint
  [name p]
  (unless (= :stroke (get p :style))
    (error (string name " requires a stroke paint")))
  p)

(defn- clear-paint
  [spec]
  (let [paint-spec (if (and (dict? spec) (has-key? spec :paint))
                     (get spec :paint)
                     spec)
        paints (paint/paints paint-spec @{})]
    (unless (= 1 (length paints))
      (error "skia/clear expects exactly one color or fill paint spec"))
    (require-fill-paint "skia/clear" (get paints 0))))

(defn clear
  [canvas spec]
  ((native-fn 'clear) canvas (clear-paint spec)))

(defn stats
  [canvas]
  ((native-fn 'stats) canvas))

(defn canvas-info
  [canvas]
  ((native-fn 'canvas-info) canvas))

(defn pixel-format
  [canvas]
  (get (canvas-info canvas) :pixel-format))

(defn width
  [canvas]
  (get (stats canvas) :width))

(defn height
  [canvas]
  (get (stats canvas) :height))

(defn draw-rect
  [canvas x y w h opts]
  (each p (draw-paints "skia/draw-rect" opts)
    ((native-fn 'draw-rect) canvas x y w h p))
  canvas)

(defn draw-rounded-rect
  [canvas x y w h radius opts]
  (each p (draw-paints "skia/draw-rounded-rect" opts)
    ((native-fn 'draw-rounded-rect) canvas x y w h radius p))
  canvas)

(defn draw-rrect
  [canvas x y w h radii opts]
  (each p (draw-paints "skia/draw-rrect" opts)
    ((native-fn 'draw-rrect) canvas x y w h radii p))
  canvas)

(defn- point-pair?
  [point]
  (and (or (= :array (type point)) (= :tuple (type point)))
       (= 2 (length point))))

(defn- flatten-points
  [points]
  (unless (or (= :array (type points)) (= :tuple (type points)))
    (error "points must be an array or tuple of [x y] pairs"))
  (def flat @[])
  (each point points
    (unless (point-pair? point)
      (error "each point must be a two-element [x y] pair"))
    (array/push flat (get point 0))
    (array/push flat (get point 1)))
  (when (< (length flat) 4)
    (error "draw-path requires at least two points"))
  flat)

(defn draw-line
  [canvas x1 y1 x2 y2 opts]
  (each p (draw-paints "skia/draw-line" opts)
    ((native-fn 'draw-line) canvas x1 y1 x2 y2 (require-stroke-paint "skia/draw-line" p)))
  canvas)

(defn draw-path
  [canvas points opts]
  (let [flat (flatten-points points)]
    (each p (draw-paints "skia/draw-path" opts)
      ((native-fn 'draw-path) canvas flat true p)))
  canvas)

(defn draw-polygon
  [canvas points opts]
  (draw-path canvas points opts))

(defn draw-triangle
  [canvas x1 y1 x2 y2 x3 y3 opts]
  (each p (draw-paints "skia/draw-triangle" opts)
    ((native-fn 'draw-triangle) canvas x1 y1 x2 y2 x3 y3 p))
  canvas)

(defn draw-circle
  [canvas cx cy radius opts]
  (each p (draw-paints "skia/draw-circle" opts)
    ((native-fn 'draw-circle) canvas cx cy radius p))
  canvas)

(defn shape-text
  [canvas text &opt opts]
  (def options (or opts @{}))
  ((native-fn 'shape-text)
    canvas
    text
    (family-name (get options :font-family nil))
    (font-size-value options)
    (font-weight-value options)
    (font-width-value options)
    (font-slant-value options)
    (font-features-string options)))

(defn text-line-metrics
  [text-line]
  ((native-fn 'text-line-metrics) text-line))

(defn draw-text-line
  [canvas text-line x y opts]
  (each p (draw-paints "skia/draw-text-line" opts)
    ((native-fn 'draw-text-line) canvas text-line x y p))
  canvas)

(defn load-png
  [path]
  ((native-fn 'load-png) path))

(defn load-svg
  [path]
  ((native-fn 'load-svg) path))

(defn load-svg-bytes
  [bytes]
  ((native-fn 'load-svg-bytes) bytes))

(defn svg-info
  [svg]
  ((native-fn 'svg-info) svg))

(defn close-svg
  [svg]
  ((native-fn 'close-svg) svg)
  nil)

(defn create-image
  [opts]
  ((native-fn 'create-image) opts))

(defn image-width
  [image]
  ((native-fn 'image-width) image))

(defn image-height
  [image]
  ((native-fn 'image-height) image))

(defn image-info
  [image]
  ((native-fn 'image-info) image))

(defn- svg-scale-key
  [opts]
  (case (get opts :scale :fit)
    :fit :meet
    :fill :slice
    (error (string "draw-svg :scale must be :fit or :fill, got " (get opts :scale)))))

(defn- svg-x-anchor
  [value]
  (case value
    nil :center
    :left :left
    :center :center
    :right :right
    0 :left
    0.5 :center
    1 :right
    (error (string "draw-svg :x must be :left, :center, :right, 0, 0.5, or 1, got " value))))

(defn- svg-y-anchor
  [value]
  (case value
    nil :center
    :top :top
    :center :center
    :bottom :bottom
    0 :top
    0.5 :center
    1 :bottom
    (error (string "draw-svg :y must be :top, :center, :bottom, 0, 0.5, or 1, got " value))))

(defn- svg-align-key
  [x y]
  (cond
    (and (= x :left) (= y :top)) :xmin-ymin
    (and (= x :center) (= y :top)) :xmid-ymin
    (and (= x :right) (= y :top)) :xmax-ymin
    (and (= x :left) (= y :center)) :xmin-ymid
    (and (= x :center) (= y :center)) :xmid-ymid
    (and (= x :right) (= y :center)) :xmax-ymid
    (and (= x :left) (= y :bottom)) :xmin-ymax
    (and (= x :center) (= y :bottom)) :xmid-ymax
    (and (= x :right) (= y :bottom)) :xmax-ymax
    :else (error (string "draw-svg could not map anchors " x " and " y))))

(defn- svg-preserve-aspect-ratio?
  [opts]
  (let [value (get opts :preserve-aspect-ratio true)]
    (cond
      (= value true) true
      (= value false) false
      :else (error (string "draw-svg :preserve-aspect-ratio must be true or false, got " value)))))

(defn- svg-align
  [opts]
  (if (svg-preserve-aspect-ratio? opts)
    (svg-align-key (svg-x-anchor (get opts :x nil))
                   (svg-y-anchor (get opts :y nil)))
    :none))

(defn draw-svg
  [canvas svg x y w h &opt opts]
  (let [options (or opts @{})]
    ((native-fn 'draw-svg) canvas svg x y w h (svg-align options) (svg-scale-key options)))
  canvas)

(defn draw-image
  [canvas image x y &opt opts]
  (let [options (or opts @{})
        source (or (get options :src) @{})
        destination (or (get options :dst) @{})
        src-x (get source :x 0)
        src-y (get source :y 0)
        src-w (get source :w (image-width image))
        src-h (get source :h (image-height image))
        dst-x (get destination :x x)
        dst-y (get destination :y y)
        dst-w (get destination :w (get options :w src-w))
        dst-h (get destination :h (get options :h src-h))
        conversion (conversion-options "skia/draw-image" options :ordered)]
    ((native-fn 'draw-image)
      canvas image
      src-x src-y src-w src-h
      dst-x dst-y dst-w dst-h
      (get options :alpha 1.0))
    (when (> (get conversion :quantize-gray-levels) 1)
      ((native-fn 'quantize-rect)
        canvas dst-x dst-y dst-w dst-h
        (get conversion :quantize-gray-levels)
        (get conversion :dither)))
    canvas))

(defn invert-rect
  [canvas x y w h]
  ((native-fn 'invert-rect) canvas x y w h)
  canvas)

(defn convert-to-gray8
  [canvas &opt opts]
  (let [conversion (conversion-options "skia/convert-to-gray8" opts :ordered)]
    ((native-fn 'convert-to-gray8) canvas (get conversion :quantize-gray-levels) (get conversion :dither))))

(defn save
  [canvas]
  ((native-fn 'save) canvas))

(defn restore
  [canvas]
  ((native-fn 'restore) canvas))

(defn translate
  [canvas x y]
  ((native-fn 'translate) canvas x y))

(defn scale
  [canvas sx sy]
  ((native-fn 'scale) canvas sx sy))

(defn clip-rect
  [canvas x y w h]
  ((native-fn 'clip-rect) canvas x y w h))

(defmacro with-save
  [canvas & body]
  (def c (gensym))
  (def result (gensym))
  ~(let [,c ,canvas]
     (skia/save ,c)
     (def ,result (protect (do ,;body)))
     (skia/restore ,c)
     (if (get ,result 0)
       (get ,result 1)
       (error (get ,result 1)))))

(defmacro with-clip-rect
  [canvas x y w h & body]
  (def c (gensym))
  ~(let [,c ,canvas]
     (skia/with-save ,c
                     (skia/clip-rect ,c ,x ,y ,w ,h)
                     ,;body)))

(defn sample-gray
  [canvas x y]
  ((native-fn 'sample-gray) canvas x y))

(defn sample-rgba
  [canvas x y]
  ((native-fn 'sample-rgba) canvas x y))

(defn present
  [& args]
  (let [[dev present-args] (split-device-args args)
        canvas (get present-args 0 nil)
        options (get present-args 1 @{})]
    (unless canvas
      (error "skia/present expects an optional device, a canvas, and optional options"))
    (device/present dev canvas (or options @{}))))

(defn run-static
  [& args]
  (let [[dev run-args] (split-device-args args)
        draw (get run-args 0 nil)
        options (get run-args 1 @{})]
    (unless draw
      (error "skia/run-static expects an optional device, a draw function, and optional options"))
    (device/run-static dev draw (or options @{}))))
