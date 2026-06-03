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

(defn native-export?
  [native-fn name]
  (get (protect (native-fn name)) 0))

(deftest desktop-native-module-registers-common-drawing-and-platform-present
  (def desktop (require-module "../lib/platform/desktop"))
  (when desktop
    (def provider-fn (module-value desktop 'provider))
    (when provider-fn
      (def native-fn (get (provider-fn) :native-fn))
      (def observed
        @{:create (native-export? native-fn 'create)
          :clear (native-export? native-fn 'clear)
          :draw-rect (native-export? native-fn 'draw-rect)
          :draw-rounded-rect (native-export? native-fn 'draw-rounded-rect)
          :draw-triangle (native-export? native-fn 'draw-triangle)
          :draw-circle (native-export? native-fn 'draw-circle)
          :shape-text (native-export? native-fn 'shape-text)
          :text-line-metrics (native-export? native-fn 'text-line-metrics)
          :draw-text-line (native-export? native-fn 'draw-text-line)
          :sample-gray (native-export? native-fn 'sample-gray)
          :stats (native-export? native-fn 'stats)
          :present (native-export? native-fn 'present)
          :fixed-viewport (native-export? native-fn 'fixed-viewport)})
      (is (deep= @{:create true
                   :clear true
                   :draw-rect true
                   :draw-rounded-rect true
                   :draw-triangle true
                   :draw-circle true
                   :shape-text true
                   :text-line-metrics true
                   :draw-text-line true
                   :sample-gray true
                   :stats true
                   :present true
                   :fixed-viewport true}
                 observed)
          "desktop native module exposes shared drawing functions plus platform presentation"))))

(run-tests!)
