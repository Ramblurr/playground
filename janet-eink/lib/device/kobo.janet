(def default-native-path "/mnt/onboard/janet-eink-demo/janet/lib/janet-skia.so")

(defn- native-path
  []
  (or (os/getenv "OTTER_SKIA_NATIVE")
      default-native-path))

(defn- module
  [self]
  (unless (get self :native-module nil)
    (put self :native-module (native (native-path))))
  (get self :native-module))

(defn native-fn
  [self name]
  (((module self) name) :value))

(defn screen-size
  [self]
  (let [fb-size ((native-fn self 'framebuffer-size))]
    @{:width (get fb-size :width)
      :height (get fb-size :height)
      :pixel-format :gray8}))

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
  [self canvas &opt options]
  (let [opts (present-options options)]
    ((native-fn self 'present) canvas (get opts :flash?) (get opts :invert-output?) (get opts :night-mode?))))

(defn input-open
  [self path &opt options]
  ((native-fn self 'input-open) path (or options {})))

(defn input-open-default
  [self &opt options]
  ((native-fn self 'input-open-scan) (or options {})))

(defn input-fdopen
  [self fd path &opt options]
  ((native-fn self 'input-fdopen) fd path (or options {})))

(defn input-close
  [self handle]
  ((native-fn self 'input-close) handle))

(defn input-close-all
  [self]
  ((native-fn self 'input-close-all)))

(defn input-wait-event
  [self timeout-ms &opt max-events]
  (if max-events
    ((native-fn self 'input-wait-event) timeout-ms max-events)
    ((native-fn self 'input-wait-event) timeout-ms)))

(defn input-poll
  [self timeout-ms &opt max-events]
  (input-wait-event self timeout-ms max-events))

(defn run-static
  [self draw &opt options]
  (let [size (screen-size self)
        canvas ((native-fn self 'create) (get size :width) (get size :height))]
    (draw canvas)
    (present self canvas (or options @{}))))

(defn close
  [self]
  (unless (get self :closed? false)
    (when (get self :native-module nil)
      (input-close-all self))
    (put self :closed? true))
  nil)

(defn make-device
  [&opt _options]
  @{:name :kobo-fbink
    :native-module nil
    :closed? false
    :native-fn native-fn
    :screen-size screen-size
    :present present
    :present-options (fn [self options] (present-options options))
    :run-static run-static
    :input-open input-open
    :input-open-default input-open-default
    :input-fdopen input-fdopen
    :input-close input-close
    :input-close-all input-close-all
    :input-wait-event input-wait-event
    :input-poll input-poll
    :close close
    :capabilities capabilities})
