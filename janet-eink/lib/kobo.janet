(def default-native-path "/mnt/onboard/janet-eink-demo/janet/lib/janet-skia.so")

(var- native-module nil)

(defn- native-path
  []
  (or (os/getenv "OTTER_KOBO_SKIA_NATIVE") default-native-path))

(defn- module
  []
  (unless native-module
    (set native-module (native (native-path))))
  native-module)

(defn- native-fn
  [name]
  (((module) name) :value))

(defn create
  [&opt width height]
  (if (and width height)
    ((native-fn 'create) width height)
    ((native-fn 'create))))

(defn clear
  [canvas gray]
  ((native-fn 'clear) canvas gray))

(defn draw-rect
  [canvas x y width height gray]
  ((native-fn 'draw-rect) canvas x y width height gray))

(defn draw-round-rect
  [canvas x y width height radius gray]
  ((native-fn 'draw-round-rect) canvas x y width height radius gray))

(defn draw-triangle
  [canvas x1 y1 x2 y2 x3 y3 gray]
  ((native-fn 'draw-triangle) canvas x1 y1 x2 y2 x3 y3 gray))

(defn draw-circle
  [canvas cx cy radius gray]
  ((native-fn 'draw-circle) canvas cx cy radius gray))

(defn sample-gray
  [canvas x y]
  ((native-fn 'sample-gray) canvas x y))

(defn stats
  [canvas]
  ((native-fn 'stats) canvas))

(defn framebuffer-size
  []
  ((native-fn 'framebuffer-size)))

(defn present
  [canvas]
  ((native-fn 'present) canvas true))

(defn run-demo
  []
  ((native-fn 'present-demo) true))
