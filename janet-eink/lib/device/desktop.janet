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
  (let [root (source-root)
        paths @[]
        override (os/getenv "OTTER_SKIA_NATIVE")]
    (when override
      (array/push paths override))
    (array/push paths (string root "/build/janet-skia.so"))
    (array/push paths (string root "/lib/janet-skia.so"))
    paths))

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

(defn- module
  [self]
  (unless (get self :native-module nil)
    (put self :native-module (native (resolve-native-path))))
  (get self :native-module))

(defn native-fn
  [self name]
  (((module self) name) :value))

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
  [& _]
  @{:width default-width
    :height default-height
    :pixel-format (pixel-format)})

(def capabilities
  @{:invert-output? true
    :night-mode? true
    :hardware-night-mode? false
    :software-dither? true
    :hardware-dither? false})

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
  [self canvas &opt options]
  (let [present-fn ((module self) 'present)]
    (unless present-fn
      (error "desktop native presenter does not yet export present"))
    ((get present-fn :value) canvas (present-options options))))

(defn fixed-viewport
  [self output-width output-height]
  ((native-fn self 'fixed-viewport) output-width output-height default-width default-height))

(defn input-open
  [self path &opt options]
  (put self :active-input-source :evdev)
  ((native-fn self 'input-open) path (or options {})))

(defn input-open-default
  [self &opt options]
  (put self :active-input-source :sdl)
  ((native-fn self 'sdl-input-open) (or options {})))

(defn input-fdopen
  [self fd path &opt options]
  (put self :active-input-source :evdev)
  ((native-fn self 'input-fdopen) fd path (or options {})))

(defn input-close
  [self handle]
  (case (get self :active-input-source nil)
    :sdl ((native-fn self 'sdl-input-close) handle)
    ((native-fn self 'input-close) handle)))

(defn input-close-all
  [self]
  (let [closed (case (get self :active-input-source nil)
                 :sdl ((native-fn self 'sdl-input-close-all))
                 :evdev ((native-fn self 'input-close-all))
                 (do
                   ((native-fn self 'sdl-input-close-all))
                   ((native-fn self 'input-close-all))))]
    (put self :active-input-source nil)
    closed))

(defn input-wait-event
  [self timeout-ms &opt max-events]
  (if max-events
    ((native-fn self 'input-wait-event) timeout-ms max-events)
    ((native-fn self 'input-wait-event) timeout-ms)))

(defn input-poll
  [self timeout-ms &opt max-events]
  (let [poll-fn (if (= (get self :active-input-source nil) :sdl)
                  (native-fn self 'sdl-input-wait-event)
                  (native-fn self 'input-wait-event))]
    (if max-events
      (poll-fn timeout-ms max-events)
      (poll-fn timeout-ms))))

(defn run-static
  [self draw &opt options]
  (let [size (screen-size self)
        canvas ((native-fn self 'create) (get size :width) (get size :height) (get size :pixel-format))]
    (draw canvas)
    (present self canvas (present-options options))))

(defn close
  [self]
  (unless (get self :closed? false)
    (when (get self :native-module nil)
      (input-close-all self))
    (put self :closed? true))
  nil)

(defn make-device
  [&opt _options]
  @{:name :desktop-sdl
    :native-module nil
    :active-input-source nil
    :closed? false
    :native-fn native-fn
    :screen-size screen-size
    :present present
    :present-options (fn [self options] (present-options options))
    :run-static run-static
    :fixed-viewport fixed-viewport
    :input-open input-open
    :input-open-default input-open-default
    :input-fdopen input-fdopen
    :input-close input-close
    :input-close-all input-close-all
    :input-wait-event input-wait-event
    :input-poll input-poll
    :close close
    :capabilities capabilities})
