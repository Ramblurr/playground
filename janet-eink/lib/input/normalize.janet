(import ./constants :as constants)

(defn new-state
  []
  @{:pressed @{}
    :modifiers @{}})

(defn- dict?
  [value]
  (or (= :table (type value)) (= :struct (type value))))

(defn- record-source
  [record]
  (get record :source nil))

(defn- source-kind
  [record]
  (let [source (record-source record)]
    (if (dict? source) (get source :kind nil) nil)))

(defn- source-value
  [record key]
  (let [source (record-source record)]
    (if (dict? source) (get source key nil) nil)))

(defn- modifier-name
  [key]
  (case key
    :left-shift :shift
    :right-shift :shift
    :left-ctrl :ctrl
    :right-ctrl :ctrl
    :left-alt :alt
    :right-alt :alt
    :left-meta :meta
    :right-meta :meta
    nil))

(defn- update-modifier!
  [state key pressed?]
  (when-let [modifier (modifier-name key)]
    (put (get state :modifiers) modifier (if pressed? true nil))))

(defn- modifiers-snapshot
  [state]
  (let [out @{}]
    (eachp [modifier active?] (get state :modifiers)
      (when active?
        (put out modifier true)))
    out))

(defn- pressed-before?
  [state code]
  (truthy? (get (get state :pressed) code false)))

(defn- update-pressed!
  [state code pressed?]
  (put (get state :pressed) code (if pressed? true nil)))

(defn- sdl-native-code
  [record fallback-code]
  (or (source-value record :sdl-keycode) fallback-code))

(defn- native-code
  [record raw-code]
  (if (= :sdl (source-kind record))
    (sdl-native-code record raw-code)
    raw-code))

(defn- semantic-key
  [record raw-code code]
  (if (= :sdl (source-kind record))
    (or (constants/sdl-key-name code)
        (constants/sdl-key-name raw-code)
        (constants/key-name raw-code)
        :unknown)
    (or (constants/key-name code) :unknown)))

(defn- key-event
  [state record]
  (let [raw-code (get record :code)
        code (native-code record raw-code)
        value (get record :value)
        key (semantic-key record raw-code code)
        pressed? (not= value 0)
        repeat? (or (= value 2)
                    (and (= value 1) (pressed-before? state code)))]
    (update-pressed! state code pressed?)
    (update-modifier! state key pressed?)
    @{:event :key
      :key key
      :pressed? pressed?
      :repeat? repeat?
      :modifiers (modifiers-snapshot state)
      :source (source-kind record)
      :native-code code
      :native-source (record-source record)
      :time (get record :time nil)}))

(defn- system-event
  [record fake-name]
  (let [code (get record :code)]
    (case fake-name
      :charging @{:event :system
                  :system :charging
                  :active? true
                  :native-code code
                  :native-source (get record :source nil)
                  :time (get record :time nil)}
      :not-charging @{:event :system
                      :system :charging
                      :active? false
                      :native-code code
                      :native-source (get record :source nil)
                      :time (get record :time nil)}
      :usb-plug-in @{:event :system
                     :system :usb-host
                     :active? true
                     :native-code code
                     :native-source (get record :source nil)
                     :time (get record :time nil)}
      :usb-plug-out @{:event :system
                      :system :usb-host
                      :active? false
                      :native-code code
                      :native-source (get record :source nil)
                      :time (get record :time nil)}
      :usb-device-plug-in @{:event :input-device
                            :action :insert
                            :native-code code
                            :native-source (get record :source nil)
                            :time (get record :time nil)}
      :usb-device-plug-out @{:event :input-device
                             :action :remove
                             :native-code code
                             :native-source (get record :source nil)
                             :time (get record :time nil)}
      :ready-to-suspend @{:event :power
                          :phase :ready-to-suspend
                          :native-code code
                          :native-source (get record :source nil)
                          :time (get record :time nil)}
      :wakeup-from-suspend @{:event :power
                             :phase :wakeup-from-suspend
                             :native-code code
                             :native-source (get record :source nil)
                             :time (get record :time nil)}
      :into-screensaver @{:event :power
                          :phase :into-screensaver
                          :native-code code
                          :native-source (get record :source nil)
                          :time (get record :time nil)}
      :out-of-screensaver @{:event :power
                            :phase :out-of-screensaver
                            :native-code code
                            :native-source (get record :source nil)
                            :time (get record :time nil)}
      :exiting-screensaver @{:event :power
                             :phase :exiting-screensaver
                             :native-code code
                             :native-source (get record :source nil)
                             :time (get record :time nil)}
      nil)))

(defn record
  [state raw-record]
  (let [type-name (constants/event-type-name (get raw-record :type nil))]
    (if (not= :ev-key type-name)
      nil
      (let [code (get raw-record :code)
            fake-name (constants/fake-system-name code)]
        (if fake-name
          (system-event raw-record fake-name)
          (key-event state raw-record))))))
