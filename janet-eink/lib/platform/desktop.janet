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

(defn- pixel-format
  []
  (case (os/getenv "OTTER_PIXEL_FORMAT" "")
    "" :rgba32
    "rgba32" :rgba32
    ":rgba32" :rgba32
    "gray8" :gray8
    ":gray8" :gray8
    (error "OTTER_PIXEL_FORMAT must be gray8 or rgba32")))

(defn screen-size
  []
  @{:width default-width
    :height default-height
    :pixel-format (pixel-format)})

(def capabilities
  @{:invert-output? true
    :night-mode? true
    :hardware-night-mode? false})

(defn- dict?
  [value]
  (or (= :table (type value)) (= :struct (type value))))

(defn- bool-option
  [opts key default]
  (if (dict? opts)
    (let [value (get opts key nil)]
      (cond
        (nil? value) default
        (or (= true value) (= false value)) value
        :else (error (string key " must be a boolean"))))
    default))

(defn present-options
  [&opt options]
  (let [opts (or options @{})
        block? (bool-option opts :block? true)
        night-mode? (bool-option opts :night-mode? false)
        invert-output? (or night-mode? (bool-option opts :invert-output? false))]
    @{:block? block?
      :invert-output? invert-output?
      :night-mode? night-mode?
      :full-refresh? (or invert-output? night-mode?)}))

(defn present
  [canvas &opt options]
  (def present-fn ((module) 'present))
  (unless present-fn
    (error "desktop native presenter does not yet export present"))
  ((get present-fn :value) canvas (present-options options)))

(defn fixed-viewport
  [output-width output-height]
  ((native-fn 'fixed-viewport) output-width output-height default-width default-height))

(defn run-static
  [draw &opt options]
  (let [size (screen-size)
        canvas ((native-fn 'create) (get size :width) (get size :height) (get size :pixel-format))]
    (draw canvas)
    (present canvas (present-options options))))

(defn provider
  []
  @{:name :desktop-sdl
    :native-fn native-fn
    :screen-size screen-size
    :present present
    :present-options present-options
    :run-static run-static
    :fixed-viewport fixed-viewport
    :capabilities capabilities})
