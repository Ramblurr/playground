(def default-native-path "/mnt/onboard/janet-eink-demo/janet/lib/janet-skia.so")

(var- native-module nil)

(defn- native-path
  []
  (or (os/getenv "OTTER_SKIA_NATIVE")
      default-native-path))

(defn- module
  []
  (unless native-module
    (set native-module (native (native-path))))
  native-module)

(defn native-fn
  [name]
  (((module) name) :value))

(defn screen-size
  []
  (def fb-size ((native-fn 'framebuffer-size)))
  @{:width (get fb-size :width)
    :height (get fb-size :height)
    :pixel-format :gray8})

(def capabilities
  @{:invert-output? true
    :night-mode? false
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
        flash? (bool-option opts :flash? true)
        invert-output? (bool-option opts :invert-output? false)
        night-mode? (bool-option opts :night-mode? false)]
    (when (and night-mode? (not (get capabilities :night-mode?)))
      (error "Kobo hardware night mode is not enabled for this presenter"))
    @{:flash? flash?
      :invert-output? invert-output?
      :night-mode? night-mode?
      :full-refresh? (or invert-output? night-mode?)}))

(defn present
  [canvas &opt options]
  (def opts (present-options options))
  ((native-fn 'present) canvas (get opts :flash?) (get opts :invert-output?) (get opts :night-mode?)))

(defn input-open
  [path &opt options]
  ((native-fn 'input-open) path (or options {})))

(defn input-open-default
  [&opt options]
  ((native-fn 'input-open-scan) (or options {})))

(defn input-fdopen
  [fd path &opt options]
  ((native-fn 'input-fdopen) fd path (or options {})))

(defn input-close
  [handle]
  ((native-fn 'input-close) handle))

(defn input-close-all
  []
  ((native-fn 'input-close-all)))

(defn input-wait-event
  [timeout-ms &opt max-events]
  (if max-events
    ((native-fn 'input-wait-event) timeout-ms max-events)
    ((native-fn 'input-wait-event) timeout-ms)))

(defn input-poll
  [timeout-ms &opt max-events]
  (input-wait-event timeout-ms max-events))

(defn run-static
  [draw &opt options]
  (def size (screen-size))
  (def canvas ((native-fn 'create) (get size :width) (get size :height)))
  (draw canvas)
  (present canvas (or options @{})))

(defn provider
  []
  @{:name :kobo-fbink
    :native-fn native-fn
    :screen-size screen-size
    :present present
    :present-options present-options
    :run-static run-static
    :input-open input-open
    :input-open-default input-open-default
    :input-fdopen input-fdopen
    :input-close input-close
    :input-close-all input-close-all
    :input-wait-event input-wait-event
    :input-poll input-poll
    :capabilities capabilities})
