(ns ol.input.kobo
  (:require
   [ol.input.evdev :as evdev]))

(def transform-profiles
  {:none          {:name       :none
                   :switch-xy? false
                   :mirror-x?  false
                   :mirror-y?  false}
   :switch-xy     {:name       :switch-xy
                   :switch-xy? true
                   :mirror-x?  false
                   :mirror-y?  false}
   :kobo-default  {:name       :kobo-default
                   :switch-xy? true
                   :mirror-x?  true
                   :mirror-y?  false}
   :kobo-mirror-y {:name       :kobo-mirror-y
                   :switch-xy? true
                   :mirror-x?  false
                   :mirror-y?  true}})

(def kobo-keymap
  {evdev/KEY_F23      :page-back
   evdev/KEY_F24      :page-forward
   evdev/KEY_HOME     :home
   evdev/KEY_POWER    :power
   evdev/KEY_H        :sleep-cover
   evdev/KEY_F1       :sleep-cover
   evdev/KEY_KATAKANA :light
   evdev/BTN_STYLUS   :eraser
   evdev/BTN_STYLUS2  :highlighter})

(defn profile
  [profile-or-keyword]
  (cond
    (map? profile-or-keyword) profile-or-keyword
    (contains? transform-profiles profile-or-keyword) (get transform-profiles profile-or-keyword)
    (nil? profile-or-keyword) (:kobo-default transform-profiles)
    :else (throw (ex-info (str "unknown Kobo input profile: " profile-or-keyword)
                          {:profile profile-or-keyword
                           :allowed (set (keys transform-profiles))}))))

(defn- viewport
  [opts]
  (or (:viewport opts)
      (when (and (:width opts) (:height opts))
        [(:width opts) (:height opts)])
      [0 0]))

(defn initial-state
  [opts]
  {:profile         (:name (profile (or (:input-profile opts) (:profile opts))))
   :profile-options (profile (or (:input-profile opts) (:profile opts)))
   :viewport        (viewport opts)
   :cur-slot        0
   :slots           {}
   :frame-slots     #{}
   :primary-slot    nil
   :last-pos        nil
   :down?           false
   :legacy          {:x nil :y nil :active? false :touched? false}
   :mt-seen?        false})

(defn transform-pos
  ([state pos]
   (transform-pos (:profile-options state) (:viewport state) pos))
  ([profile-or-keyword viewport [x y]]
   (let [{:keys [switch-xy? mirror-x? mirror-y?]} (profile profile-or-keyword)
         [w h]                                    viewport
         [x y]                                    (if switch-xy? [y x] [x y])
         x                                        (if mirror-x? (- w x) x)
         y                                        (if mirror-y? (- h y) y)]
     [x y])))

(defn- reset-touch-state
  [state]
  (assoc state
         :cur-slot 0
         :slots {}
         :frame-slots #{}
         :primary-slot nil
         :last-pos nil
         :down? false
         :legacy {:x nil :y nil :active? false :touched? false}
         :mt-seen? false))

(defn- mark-frame-slot
  [state slot]
  (update state :frame-slots (fnil conj #{}) slot))

(defn- update-current-slot
  [state f & args]
  (let [slot (:cur-slot state)]
    (-> state
        (update-in [:slots slot] #(apply f (or % {}) args))
        (mark-frame-slot slot))))

(defn- active-slot?
  [[_slot slot-data]]
  (and (some? (:tracking-id slot-data))
       (not= -1 (:tracking-id slot-data))))

(defn- slot-pos
  [slot-data]
  (when (and (some? (:x slot-data))
             (some? (:y slot-data)))
    [(:x slot-data) (:y slot-data)]))

(defn- primary-candidate
  [state]
  (or (when-let [slot (:primary-slot state)]
        (when-let [slot-data (get-in state [:slots slot])]
          (when (active-slot? [slot slot-data])
            [slot slot-data])))
      (first (filter (fn [[_slot slot-data]]
                       (and (active-slot? [_slot slot-data])
                            (slot-pos slot-data)))
                     (sort-by key (:slots state))))))

(defn- touch-event
  [kind pos raw]
  {:kind kind
   :pos  pos
   :raw  raw})

(defn- emit-mt-frame
  [state raw]
  (let [[slot slot-data :as primary] (primary-candidate state)]
    (cond
      (and (not (:down? state)) primary (slot-pos slot-data))
      (let [pos (transform-pos state (slot-pos slot-data))]
        {:state  (assoc state
                        :down? true
                        :primary-slot slot
                        :last-pos pos
                        :frame-slots #{})
         :events [(touch-event :touch-down pos raw)]})

      (and (:down? state) (not primary))
      (let [pos (:last-pos state)]
        {:state  (assoc state
                        :down? false
                        :primary-slot nil
                        :frame-slots #{})
         :events (if pos [(touch-event :touch-up pos raw)] [])})

      (and (:down? state) primary (slot-pos slot-data))
      (let [pos (transform-pos state (slot-pos slot-data))]
        {:state  (assoc state
                        :last-pos pos
                        :frame-slots #{})
         :events (if (and (seq (:frame-slots state))
                          (not= pos (:last-pos state)))
                   [(touch-event :touch-move pos raw)]
                   [])})

      :else
      {:state  (assoc state :frame-slots #{})
       :events []})))

(defn- legacy-pos
  [state]
  (let [{:keys [x y]} (:legacy state)]
    (when (and (some? x) (some? y))
      [x y])))

(defn- emit-legacy-frame
  [state raw]
  (let [{:keys [active? touched?]} (:legacy state)]
    (cond
      (and touched? (not (:down? state)) active? (legacy-pos state))
      (let [pos (transform-pos state (legacy-pos state))]
        {:state  (-> state
                     (assoc :down? true
                            :last-pos pos)
                     (assoc-in [:legacy :touched?] false))
         :events [(touch-event :touch-down pos raw)]})

      (and touched? (:down? state) (not active?))
      (let [pos (:last-pos state)]
        {:state  (-> state
                     (assoc :down? false)
                     (assoc-in [:legacy :touched?] false))
         :events (if pos [(touch-event :touch-up pos raw)] [])})

      (and touched? (:down? state) active? (legacy-pos state))
      (let [pos (transform-pos state (legacy-pos state))]
        {:state  (-> state
                     (assoc :last-pos pos)
                     (assoc-in [:legacy :touched?] false))
         :events (if (not= pos (:last-pos state))
                   [(touch-event :touch-move pos raw)]
                   [])})

      :else
      {:state  (assoc-in state [:legacy :touched?] false)
       :events []})))

(defn- emit-touch-frame
  [state raw]
  (if (:mt-seen? state)
    (emit-mt-frame state raw)
    (emit-legacy-frame state raw)))

(defn- handle-abs
  [state {:keys [code value]}]
  (condp = code
    evdev/ABS_MT_SLOT
    (assoc state :cur-slot value :mt-seen? true)

    evdev/ABS_MT_TRACKING_ID
    (-> state
        (assoc :mt-seen? true)
        (update-current-slot assoc :tracking-id value))

    evdev/ABS_MT_POSITION_X
    (-> state
        (assoc :mt-seen? true)
        (update-current-slot assoc :x value))

    evdev/ABS_MT_POSITION_Y
    (-> state
        (assoc :mt-seen? true)
        (update-current-slot assoc :y value))

    evdev/ABS_MT_TOOL_TYPE
    (-> state
        (assoc :mt-seen? true)
        (update-current-slot assoc :tool value))

    evdev/ABS_MT_TOUCH_MAJOR
    (-> state
        (assoc :mt-seen? true)
        (update-current-slot assoc :touch-major value))

    evdev/ABS_MT_PRESSURE
    state

    evdev/ABS_MT_TOUCH_MINOR
    state

    evdev/ABS_MT_ORIENTATION
    state

    evdev/ABS_MT_DISTANCE
    state

    evdev/ABS_X
    (if (:mt-seen? state)
      state
      (-> state
          (assoc-in [:legacy :x] value)
          (assoc-in [:legacy :touched?] true)))

    evdev/ABS_Y
    (if (:mt-seen? state)
      state
      (-> state
          (assoc-in [:legacy :y] value)
          (assoc-in [:legacy :touched?] true)))

    evdev/ABS_PRESSURE
    (if (:mt-seen? state)
      state
      (-> state
          (assoc-in [:legacy :active?] (pos? value))
          (assoc-in [:legacy :touched?] true)))

    state))

(def touch-key-codes
  #{evdev/BTN_TOOL_FINGER
    evdev/BTN_TOUCH})

(defn- handle-touch-key
  [state value]
  (if (:mt-seen? state)
    (if (zero? value)
      (update-current-slot state assoc :tracking-id -1)
      state)
    (-> state
        (assoc-in [:legacy :active?] (pos? value))
        (assoc-in [:legacy :touched?] true))))

(defn- handle-key
  [state {:keys [code value] :as raw}]
  (if (contains? touch-key-codes code)
    {:state  (handle-touch-key state value)
     :events []}
    (let [action (evdev/key-action value)]
      {:state  state
       :events (when action
                 [(if-let [k (get kobo-keymap code)]
                    {:kind :key :key k :action action :raw raw}
                    {:kind :unknown-key :code code :action action :raw raw})])})))

(defn accept-raw-event
  [state {:keys [type code] :as raw}]
  (condp = type
    evdev/EV_ABS
    {:state  (handle-abs state raw)
     :events []}

    evdev/EV_KEY
    (handle-key state raw)

    evdev/EV_SYN
    (condp = code
      evdev/SYN_REPORT
      (emit-touch-frame state raw)

      evdev/SYN_DROPPED
      {:state  (reset-touch-state state)
       :events [{:kind :syn-dropped :raw raw}]}

      {:state state :events []})

    {:state state :events []}))

(defn accept-raw-events
  [state raw-events]
  (reduce (fn [{:keys [state events]} raw]
            (let [{next-state :state new-events :events} (accept-raw-event state raw)]
              {:state  next-state
               :events (into events new-events)}))
          {:state  state
           :events []}
          raw-events))
