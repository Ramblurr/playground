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

(defn render-hello-self-test
  []
  ((native-fn 'render-self-test) default-width default-height))

(defn fixed-viewport
  [output-width output-height]
  ((native-fn 'fixed-viewport) output-width output-height default-width default-height))

(defn run-hello
  []
  ((native-fn 'run-hello) default-width default-height))
