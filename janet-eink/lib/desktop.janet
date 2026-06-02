(def default-width 1680)
(def default-height 1264)

(defn- dirname
  [path]
  (var i (- (length path) 1))
  (while (and (>= i 0) (not= (get path i) (chr "/")))
    (-- i))
  (if (< i 0) "." (string/slice path 0 i)))

(defn- source-root
  []
  (dirname (dirname (os/realpath (dyn :current-file)))))

(defn- file?
  [path]
  (= :file (os/stat path :mode)))

(defn- push-env
  [paths name]
  (def value (os/getenv name))
  (when value
    (array/push paths value)))

(defn- candidate-native-paths
  []
  (def root (source-root))
  (def paths @[])
  (push-env paths "OTTER_DESKTOP_NATIVE")
  (array/push paths (string root "/build/janet-otter-sdl.so"))
  (array/push paths (string root "/lib/janet-otter-sdl.so"))
  (push-env paths "OTTER_DESKTOP_NATIVE_FALLBACK")
  paths)

(defn- resolve-native-path
  []
  (var selected nil)
  (each path (candidate-native-paths)
    (when (and (not selected) (file? path))
      (set selected path)))
  (unless selected
    (error (string "could not find janet-otter-sdl native module; run `make native` "
                   "or set OTTER_DESKTOP_NATIVE=/path/to/janet-otter-sdl.so")))
  selected)

(var- native-module nil)

(defn- module
  []
  (unless native-module
    (set native-module (native (resolve-native-path))))
  native-module)

(defn- native-fn
  [name]
  (((module) name) :value))

(defn create
  [&opt width height]
  ((native-fn 'create) (or width default-width) (or height default-height)))

(defn clear
  [canvas gray]
  ((native-fn 'clear) canvas gray))

(defn draw-rect
  [canvas x y width height gray]
  ((native-fn 'draw-rect) canvas x y width height gray))

(defn draw-round-rect
  [canvas x y width height radius gray]
  ((native-fn 'draw-round-rect) canvas x y width height radius gray))

(defn draw-triangle
  [canvas x1 y1 x2 y2 x3 y3 gray]
  ((native-fn 'draw-triangle) canvas x1 y1 x2 y2 x3 y3 gray))

(defn draw-circle
  [canvas cx cy radius gray]
  ((native-fn 'draw-circle) canvas cx cy radius gray))

(defn sample-gray
  [canvas x y]
  ((native-fn 'sample-gray) canvas x y))

(defn stats
  [canvas]
  ((native-fn 'stats) canvas))

(defn render-demo-self-test
  []
  ((native-fn 'render-demo-self-test) default-width default-height))

(defn fixed-viewport
  [output-width output-height]
  ((native-fn 'fixed-viewport) output-width output-height default-width default-height))

(defn run-demo
  []
  ((native-fn 'run-demo) default-width default-height))
