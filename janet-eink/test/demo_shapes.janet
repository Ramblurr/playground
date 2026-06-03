(use ../deps/testament)

(defn require-module
  [path]
  (def result (protect (require path :fresh true)))
  (if (get result 0)
    (get result 1)
    (do
      (is false (string "expected module " path " to load: " (get result 1)))
      nil)))

(defn module-value
  [module name]
  (def binding (get module name))
  (if binding
    (get binding :value)
    (do
      (is false (string "expected module to export " name))
      nil)))

(deftest janet-shape-demo-renders-through-public-skia-api
  (def skia (require-module "../lib/skia"))
  (def shapes (require-module "../lib/demo/shapes"))
  (when (and skia shapes)
    (def create (module-value skia 'create))
    (def stats-fn (module-value skia 'stats))
    (def draw (module-value shapes 'draw))
    (when (and create stats-fn draw)
      (def frame (create 1264 1680))
      (draw frame)
      (def stats (stats-fn frame))
      (def observed
        @{:width (get stats :width)
          :height (get stats :height)
          :pixel-format (get stats :pixel-format)
          :has-black? (= 0 (get stats :min-gray))
          :has-white? (= 255 (get stats :max-gray))
          :many-shades? (>= (get stats :gray-shades) 8)
          :substantial-ink? (> (get stats :non-white-pixels) 200000)
          :non-empty? (> (get stats :checksum) 0)})
      (is (deep= @{:width 1264
                   :height 1680
                   :pixel-format :gray8
                   :has-black? true
                   :has-white? true
                   :many-shades? true
                   :substantial-ink? true
                   :non-empty? true}
                 observed)
          "Janet-owned shape demo renders substantial portrait gray8 geometry through lib/skia.janet"))))

(run-tests!)
