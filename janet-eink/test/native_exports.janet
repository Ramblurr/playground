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

(defn select-fields
  [table keys]
  (def out @{})
  (each key keys
    (when (has-key? table key)
      (put out key (get table key))))
  out)

(deftest desktop-native-module-registers-common-drawing-and-device-present
  (def device-module (require-module "../lib/device"))
  (when device-module
    (def make-device (module-value device-module 'make-device))
    (when make-device
      (def dev (make-device :desktop-sdl))
      (def native-fn (fn [name] (:native-fn dev name)))
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
          :sample-rgba (native-export? native-fn 'sample-rgba)
          :canvas-info (native-export? native-fn 'canvas-info)
          :convert-to-gray8 (native-export? native-fn 'convert-to-gray8)
          :quantize-rect (native-export? native-fn 'quantize-rect)
          :stats (native-export? native-fn 'stats)
          :present (native-export? native-fn 'present)
          :fixed-viewport (native-export? native-fn 'fixed-viewport)
          :input-open (native-export? native-fn 'input-open)
          :input-fdopen (native-export? native-fn 'input-fdopen)
          :input-close (native-export? native-fn 'input-close)
          :input-close-all (native-export? native-fn 'input-close-all)
          :input-wait-event (native-export? native-fn 'input-wait-event)
          :sdl-input-open (native-export? native-fn 'sdl-input-open)
          :sdl-input-close (native-export? native-fn 'sdl-input-close)
          :sdl-input-close-all (native-export? native-fn 'sdl-input-close-all)
          :sdl-input-wait-event (native-export? native-fn 'sdl-input-wait-event)})
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
                   :sample-rgba true
                   :canvas-info true
                   :convert-to-gray8 true
                   :quantize-rect true
                   :stats true
                   :present true
                   :fixed-viewport true
                   :input-open true
                   :input-fdopen true
                   :input-close true
                   :input-close-all true
                   :input-wait-event true
                   :sdl-input-open true
                   :sdl-input-close true
                   :sdl-input-close-all true
                   :sdl-input-wait-event true}
                 observed)
          "desktop native module exposes shared drawing functions plus device presentation"))))

(deftest desktop-native-input-noninteractive-smoke
  (def device-module (require-module "../lib/device"))
  (when device-module
    (def make-device (module-value device-module 'make-device))
    (when make-device
      (def dev (make-device :desktop-sdl))
      (def native-fn (fn [name] (:native-fn dev name)))
      (def input-open (native-fn 'input-open))
      (def input-fdopen (native-fn 'input-fdopen))
      (def close-all (native-fn 'input-close-all))
      (def wait-event (native-fn 'input-wait-event))
      (close-all)
      (def observed @{:wait-no-handles (wait-event 0)
                      :open-missing (select-fields (input-open "/dev/input/otter-missing" @{}) [:operation])
                      :fdopen-bad (select-fields (input-fdopen -1 "bad-fd" @{}) [:operation :error])})
      (close-all)
      (is (deep= @{:wait-no-handles @{:timeout? true :events @[]}
                   :open-missing @{:operation "open"}
                   :fdopen-bad @{:operation "fdopen" :error 9}}
                 observed)
          "input native exports support noninteractive timeout and error smokes"))))

(run-tests!)
