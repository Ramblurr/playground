(import ./device/desktop :as desktop)
(import ./device/kobo :as kobo)

(def Device
  @{:otter/device? true
    :close (fn [self] nil)})

(var- current-device nil)

(defn- dict?
  [value]
  (or (= :table (type value)) (= :struct (type value))))

(defn device?
  [value]
  (and (dict? value) (= true (get value :otter/device? false))))

(defn- directory?
  [path]
  (= :directory (os/stat path :mode)))

(defn kobo?
  []
  (or (directory? "/mnt/onboard/.kobo")
      (directory? "/mnt/onboard")))

(defn- non-empty-env
  [name]
  (let [value (os/getenv name)]
    (if (= value "") nil value)))

(defn detect-backend
  []
  (let [override (or (non-empty-env "OTTER_DEVICE") (non-empty-env "OTTER_PLATFORM"))]
    (cond
      (= override "desktop-sdl") :desktop-sdl
      (= override "kobo-fbink") :kobo-fbink
      (= override "kobo") :kobo-fbink
      (os/getenv "KOBO_DEVICE") :kobo-fbink
      (kobo?) :kobo-fbink
      :else :desktop-sdl)))

(defn- normalize-backend
  [backend]
  (case backend
    nil (detect-backend)
    :desktop-sdl :desktop-sdl
    "desktop-sdl" :desktop-sdl
    :kobo-fbink :kobo-fbink
    "kobo-fbink" :kobo-fbink
    :kobo :kobo-fbink
    "kobo" :kobo-fbink
    (error (string "unsupported Otter device backend: " backend))))

(defn make-device
  [backend &opt options]
  (let [opts (or options @{})
        selected (normalize-backend backend)
        dev (cond
              (= selected :desktop-sdl) (desktop/make-device opts)
              (= selected :kobo-fbink) (kobo/make-device opts)
              :else (error (string "unsupported Otter device backend: " selected)))]
    (unless (dict? dev)
      (error "device factory must return a table"))
    (table/setproto dev Device)
    dev))

(defn set-current!
  [dev]
  (unless (device? dev)
    (error "set-current! expects an Otter Device"))
  (set current-device dev)
  dev)

(defn clear-current!
  []
  (set current-device nil)
  nil)

(defn detect
  [&opt options]
  (let [opts (or options @{})
        dev (make-device (get opts :backend nil) opts)]
    (set-current! dev)))

(defn current
  []
  (unless current-device
    (set-current! (detect)))
  current-device)

(defn close
  [dev]
  (when (device? dev)
    (:close dev))
  nil)

(defn native-fn
  [dev name]
  (:native-fn dev name))

(defn screen-size
  [dev]
  (:screen-size dev))

(defn present
  [dev canvas &opt options]
  (:present dev canvas (or options @{})))

(defn input-open
  [dev path &opt options]
  (:input-open dev path (or options {})))

(defn input-open-default
  [dev &opt options]
  (:input-open-default dev (or options {})))

(defn input-fdopen
  [dev fd path &opt options]
  (:input-fdopen dev fd path (or options {})))

(defn input-close
  [dev handle]
  (:input-close dev handle))

(defn input-close-all
  [dev]
  (:input-close-all dev))

(defn input-wait-event
  [dev timeout-ms &opt max-events]
  (:input-wait-event dev timeout-ms max-events))

(defn input-poll
  [dev timeout-ms &opt max-events]
  (:input-poll dev timeout-ms max-events))

(defn run-static
  [dev draw &opt options]
  (:run-static dev draw (or options @{})))
