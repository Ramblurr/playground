(import ./skia :as skia)
(import ./demo/shapes :as shapes)

(defn run
  [& args]
  (skia/run-static shapes/draw))
