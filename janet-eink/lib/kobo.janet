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

(defn run-hello
  []
  ((native-fn 'render-hello)))
