(import ./paint :as paint)
(import ./platform :as platform)

(defn- native-fn
  [name]
  (platform/native-fn name))

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
  []
  (platform/screen-size))

(defn- create-native
  [width height pixel-format font-dir default-family]
  (if font-dir
    ((native-fn 'create) width height pixel-format font-dir default-family)
    ((native-fn 'create) width height pixel-format)))

(defn create
  [& args]
  (case (length args)
    0 (let [size (screen-size)]
        (create-native (get size :width) (get size :height) (get size :pixel-format :gray8) (default-font-dir) "Noto Sans"))
    1 (let [opts (get args 0)]
        (unless (or (= :table (type opts)) (= :struct (type opts)))
          (error "skia/create with one argument expects an options table"))
        (let [size (screen-size)]
          (create-native (get opts :width)
                         (get opts :height)
                         (get opts :pixel-format (get size :pixel-format :gray8))
                         (font-dir-value opts)
                         (family-name (get opts :font :sans)))))
    2 (create-native (get args 0) (get args 1) :gray8 (default-font-dir) "Noto Sans")
    (error "skia/create expects zero args, width/height, or an options table")))

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

(defn image-width
  [image]
  ((native-fn 'image-width) image))

(defn image-height
  [image]
  ((native-fn 'image-height) image))

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
        dst-h (get destination :h (get options :h src-h))]
    ((native-fn 'draw-image)
     canvas image
     src-x src-y src-w src-h
     dst-x dst-y dst-w dst-h
     (get options :alpha 1.0))))

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
  [canvas &opt options]
  (platform/present canvas (or options @{})))

(defn run-static
  [draw &opt options]
  (platform/run-static draw (or options @{})))
