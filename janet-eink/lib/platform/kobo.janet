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

(defn present
  [canvas &opt options]
  (def opts (or options @{}))
  ((native-fn 'present) canvas (get opts :flash? true)))

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
    :run-static run-static})
