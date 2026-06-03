(def default-width 1264)
(def default-height 1680)

(defn- dirname
  [path]
  (var i (- (length path) 1))
  (while (and (>= i 0) (not= (get path i) (chr "/")))
    (-- i))
  (if (< i 0) "." (string/slice path 0 i)))

(def- module-file (os/realpath (dyn :current-file)))
(def- module-root (dirname (dirname (dirname module-file))))

(defn- source-root
  []
  module-root)

(defn- file?
  [path]
  (= :file (os/stat path :mode)))

(defn- candidate-native-paths
  []
  (def root (source-root))
  (def paths @[])
  (def override (os/getenv "OTTER_SKIA_NATIVE"))
  (when override
    (array/push paths override))
  (array/push paths (string root "/build/janet-skia.so"))
  (array/push paths (string root "/lib/janet-skia.so"))
  paths)

(defn- resolve-native-path
  []
  (var selected nil)
  (each path (candidate-native-paths)
    (when (and (not selected) (file? path))
      (set selected path)))
  (unless selected
    (error (string "could not find janet-skia desktop native module; run `make native` "
                   "or set OTTER_SKIA_NATIVE=/path/to/janet-skia.so")))
  selected)

(var- native-module nil)

(defn- module
  []
  (unless native-module
    (set native-module (native (resolve-native-path))))
  native-module)

(defn native-fn
  [name]
  (((module) name) :value))

(defn screen-size
  []
  @{:width default-width
    :height default-height
    :pixel-format :gray8})

(defn present
  [canvas &opt options]
  (def present-fn ((module) 'present))
  (unless present-fn
    (error "desktop native presenter does not yet export present"))
  ((get present-fn :value) canvas (or options @{})))

(defn fixed-viewport
  [output-width output-height]
  ((native-fn 'fixed-viewport) output-width output-height default-width default-height))

(defn run-static
  [draw &opt options]
  (def size (screen-size))
  (def canvas ((native-fn 'create) (get size :width) (get size :height)))
  (draw canvas)
  (present canvas (or options @{})))

(defn provider
  []
  @{:name :desktop-sdl
    :native-fn native-fn
    :screen-size screen-size
    :present present
    :run-static run-static
    :fixed-viewport fixed-viewport})
