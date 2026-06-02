(import ./platform/desktop :as desktop)
(import ./platform/kobo :as kobo)

(defn- directory?
  [path]
  (= :directory (os/stat path :mode)))

(defn kobo?
  []
  (or (directory? "/mnt/onboard/.kobo")
      (directory? "/mnt/onboard")))

(defn detect
  []
  (def override (os/getenv "OTTER_PLATFORM"))
  (cond
    (= override "desktop-sdl") :desktop-sdl
    (= override "kobo-fbink") :kobo-fbink
    (= override "kobo") :kobo-fbink
    (os/getenv "KOBO_DEVICE") :kobo-fbink
    (kobo?) :kobo-fbink
    :else :desktop-sdl))

(defn provider
  [&opt backend]
  (def selected (or backend (detect)))
  (cond
    (= selected :desktop-sdl) (desktop/provider)
    (= selected :kobo-fbink) (kobo/provider)
    :else (error (string "unsupported Otter backend: " selected))))

(defn native-fn
  [name]
  (((provider) :native-fn) name))

(defn screen-size
  []
  (((provider) :screen-size)))

(defn present
  [canvas &opt options]
  (((provider) :present) canvas (or options @{})))

(defn run-static
  [draw &opt options]
  (((provider) :run-static) draw (or options @{})))
