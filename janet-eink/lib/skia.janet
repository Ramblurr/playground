(import ./platform :as platform)

(def black 0)
(def dark-gray 96)
(def gray 170)
(def light-gray 224)
(def white 255)

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

(defn- text-size-value
  [opts]
  (get opts :size 16))

(defn- gray-value
  [value]
  (cond
    (nil? value) black
    (= :number (type value)) value
    (or (= :table (type value)) (= :struct (type value))) (get value :gray black)
    :else (error (string "expected gray number or paint table, got " (type value)))))


(defn- paint-key
  [value key default]
  (if (or (= :table (type value)) (= :struct (type value)))
    (get value key default)
    default))

(defn- stroke-width-value
  [value]
  (paint-key value :stroke-width 1))
(defn paint
  [&opt options]
  (def opts (or options @{}))
  @{:gray (gray-value (get opts :gray black))
    :alpha (get opts :alpha 1.0)
    :style (get opts :style :fill)
    :stroke-width (get opts :stroke-width 1)
    :anti-alias? (get opts :anti-alias? false)})

(defn with-paint
  [base overrides]
  (merge (paint base) overrides))

(defn screen-size
  []
  (platform/screen-size))

(defn- create-native
  [width height font-dir default-family]
  (if font-dir
    ((native-fn 'create) width height font-dir default-family)
    ((native-fn 'create) width height)))

(defn create
  [& args]
  (case (length args)
    0 (do
        (def size (screen-size))
        (create-native (get size :width) (get size :height) (default-font-dir) "Noto Sans"))
    1 (do
        (def opts (get args 0))
        (unless (or (= :table (type opts)) (= :struct (type opts)))
          (error "skia/create with one argument expects an options table"))
        (create-native (get opts :width)
                       (get opts :height)
                       (font-dir-value opts)
                       (family-name (get opts :font :sans))))
    2 (create-native (get args 0) (get args 1) (default-font-dir) "Noto Sans")
    (error "skia/create expects zero args, width/height, or an options table")))

(defn clear
  [canvas value]
  ((native-fn 'clear) canvas (gray-value value)))

(defn stats
  [canvas]
  ((native-fn 'stats) canvas))

(defn width
  [canvas]
  (get (stats canvas) :width))

(defn height
  [canvas]
  (get (stats canvas) :height))

(defn draw-rect
  [canvas x y w h &opt p]
  ((native-fn 'draw-rect) canvas x y w h (gray-value p)))

(defn draw-rounded-rect
  [canvas x y w h radius &opt p]
  ((native-fn 'draw-rounded-rect) canvas x y w h radius (gray-value p)))

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
  [canvas x1 y1 x2 y2 &opt p]
  ((native-fn 'draw-line) canvas x1 y1 x2 y2 (gray-value p) (stroke-width-value p)))

(defn draw-path
  [canvas points &opt p]
  ((native-fn 'draw-path) canvas (flatten-points points) true (gray-value p)))

(defn draw-polygon
  [canvas points &opt p]
  (draw-path canvas points p))

(defn draw-triangle
  [canvas x1 y1 x2 y2 x3 y3 &opt p]
  ((native-fn 'draw-triangle) canvas x1 y1 x2 y2 x3 y3 (gray-value p)))

(defn draw-circle
  [canvas cx cy radius &opt p]
  ((native-fn 'draw-circle) canvas cx cy radius (gray-value p)))

(defn measure-text
  [canvas text &opt opts]
  (def options (or opts @{}))
  ((native-fn 'measure-text)
   canvas
   text
   (family-name (or (get options :family) (get options :font)))
   (text-size-value options)
   (weight-value (get options :weight))))

(defn draw-text
  [canvas text x y &opt opts]
  (def options (or opts @{}))
  ((native-fn 'draw-text)
   canvas
   text
   x
   y
   (family-name (or (get options :family) (get options :font)))
   (text-size-value options)
   (weight-value (get options :weight))
   (gray-value options)))

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

(defn present
  [canvas &opt options]
  (platform/present canvas (or options @{})))

(defn run-static
  [draw &opt options]
  (platform/run-static draw (or options @{})))
