(use ../deps/testament)

(defn require-module
  [path]
  (let [result (protect (require path :fresh true))]
    (if (get result 0)
      (get result 1)
      (do
        (is false (string "expected module " path " to load: " (get result 1)))
        nil))))

(defn module-value
  [module name]
  (let [binding (get module name)]
    (if binding
      (get binding :value)
      (do
        (is false (string "expected module to export " name))
        nil))))

(defn method?
  [value key]
  (= :function (type (get value key))))

(defn device-summary
  [device-module dev]
  (let [device? (module-value device-module 'device?)]
    @{:name (get dev :name)
      :device? (device? dev)
      :native-fn? (method? dev :native-fn)
      :screen-size? (method? dev :screen-size)
      :present? (method? dev :present)
      :present-options? (method? dev :present-options)
      :run-static? (method? dev :run-static)
      :input-open? (method? dev :input-open)
      :input-open-default? (method? dev :input-open-default)
      :input-fdopen? (method? dev :input-fdopen)
      :input-close? (method? dev :input-close)
      :input-close-all? (method? dev :input-close-all)
      :input-wait-event? (method? dev :input-wait-event)
      :input-poll? (method? dev :input-poll)
      :close? (method? dev :close)
      :capabilities (get dev :capabilities)}))

(deftest desktop-device-factory-returns-device-handle
  (let [device-module (require-module "../lib/device")]
    (when device-module
      (let [make-device (module-value device-module 'make-device)]
        (when make-device
          (let [observed (device-summary device-module (make-device :desktop-sdl))]
            (is (deep= @{:name :desktop-sdl
                         :device? true
                         :native-fn? true
                         :screen-size? true
                         :present? true
                         :present-options? true
                         :run-static? true
                         :input-open? true
                         :input-open-default? true
                         :input-fdopen? true
                         :input-close? true
                         :input-close-all? true
                         :input-wait-event? true
                         :input-poll? true
                         :close? true
                         :capabilities @{:invert-output? true
                                         :night-mode? true
                                         :hardware-night-mode? false
                                         :software-dither? true
                                         :hardware-dither? false}}
                       observed)
                "desktop factory returns one process-lifetime device handle")))))))

(deftest kobo-device-factory-returns-device-handle
  (let [device-module (require-module "../lib/device")]
    (when device-module
      (let [make-device (module-value device-module 'make-device)]
        (when make-device
          (let [observed (device-summary device-module (make-device :kobo-fbink))]
            (is (deep= @{:name :kobo-fbink
                         :device? true
                         :native-fn? true
                         :screen-size? true
                         :present? true
                         :present-options? true
                         :run-static? true
                         :input-open? true
                         :input-open-default? true
                         :input-fdopen? true
                         :input-close? true
                         :input-close-all? true
                         :input-wait-event? true
                         :input-poll? true
                         :close? true
                         :capabilities @{:invert-output? true
                                         :night-mode? false
                                         :hardware-night-mode? false
                                         :software-dither? true
                                         :hardware-dither? false}}
                       observed)
                "Kobo factory returns one process-lifetime device handle")))))))

(deftest detect-honors-otter-device-once-and-returns-device
  (let [device-module (require-module "../lib/device")]
    (when device-module
      (let [detect (module-value device-module 'detect)
            device? (module-value device-module 'device?)
            original (os/getenv "OTTER_DEVICE" "")]
        (when (and detect device?)
          (os/setenv "OTTER_DEVICE" "desktop-sdl")
          (let [dev (detect)]
            (os/setenv "OTTER_DEVICE" original)
            (is (= :desktop-sdl (get dev :name))
                "device detection returns the selected backend handle")
            (is (device? dev)
                "detected backend is a Device instance")))))))

(deftest input-facade-requires-explicit-device-handle
  (let [device-module (require-module "../lib/device")
        input-module (require-module "../lib/input")]
    (when (and device-module input-module)
      (let [Device (module-value device-module 'Device)
            open (module-value input-module 'open)
            open-default (module-value input-module 'open-default)
            poll (module-value input-module 'poll)
            close (module-value input-module 'close)
            close-all (module-value input-module 'close-all)]
        (when (and Device open open-default poll close close-all)
          (let [calls @[]
                fake (table/setproto @{:name :fake-device
                                        :input-open (fn [self path opts]
                                                      (array/push calls [:open (get self :name) path opts])
                                                      :opened)
                                        :input-open-default (fn [self opts]
                                                              (array/push calls [:open-default (get self :name) opts])
                                                              :opened-default)
                                        :input-poll (fn [self timeout-ms max-events]
                                                      (array/push calls [:poll (get self :name) timeout-ms max-events])
                                                      @{:timeout? true})
                                        :input-close (fn [self handle]
                                                       (array/push calls [:close (get self :name) handle])
                                                       true)
                                        :input-close-all (fn [self]
                                                           (array/push calls [:close-all (get self :name)])
                                                           true)}
                                      Device)
                open-result (open fake "/dev/input/test" {:grab? false})
                open-default-result (open-default fake {:grab? true})
                poll-result (poll fake 25 3)
                close-result (close fake :opened)
                close-all-result (close-all fake)
                observed @{:open open-result
                            :open-default open-default-result
                            :poll poll-result
                            :close close-result
                            :close-all close-all-result
                            :calls calls}]
            (is (deep= @{:open :opened
                         :open-default :opened-default
                         :poll @{:timeout? true}
                         :close true
                         :close-all true
                         :calls @[[ :open :fake-device "/dev/input/test" {:grab? false}]
                                  [ :open-default :fake-device {:grab? true}]
                                  [ :poll :fake-device 25 3]
                                  [ :close :fake-device :opened]
                                  [ :close-all :fake-device]]}
                       observed)
                "input facade dispatches through the explicit Device handle")))))))

(run-tests!)
