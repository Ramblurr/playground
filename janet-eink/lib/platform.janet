(import ./desktop :as desktop)
(import ./kobo :as kobo)

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

(defn run-hello
  []
  (def backend (detect))
  (cond
    (= backend :desktop-sdl) (desktop/run-hello)
    (= backend :kobo-fbink) (kobo/run-hello)
    :else (error (string "unsupported Otter backend: " backend))))
