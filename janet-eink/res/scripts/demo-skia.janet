(defn- dirname
  [path]
  (var i (- (length path) 1))
  (while (and (>= i 0) (not= (get path i) (chr "/")))
    (-- i))
  (if (< i 0) "." (string/slice path 0 i)))

(def script-path (os/realpath (dyn :current-file)))
(def root (dirname (dirname (dirname script-path))))
(setdyn :syspath root)

(import otter/lib/skia :as skia)
(import otter/lib/demo/shapes :as shapes)

(skia/run-static shapes/draw)
