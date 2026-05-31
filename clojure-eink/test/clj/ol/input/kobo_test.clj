(ns ol.input.kobo-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [ol.input.evdev :as evdev]
   [ol.input.kobo :as kobo]))

(defn- raw-event
  ([type code value]
   (raw-event type code value nil))
  ([type code value overrides]
   (merge {:sec          0
           :usec         0
           :type         type
           :code         code
           :value        value
           :device-index 0
           :device-type  0}
          overrides)))

(defn- strip-raw
  [events]
  (mapv #(dissoc % :raw) events))

(defn- accept
  [opts raw-events]
  (kobo/accept-raw-events (kobo/initial-state opts) raw-events))

(defn- mt-down-frame
  [[x y]]
  [(raw-event evdev/EV_ABS evdev/ABS_MT_SLOT 0)
   (raw-event evdev/EV_ABS evdev/ABS_MT_TRACKING_ID 42)
   (raw-event evdev/EV_ABS evdev/ABS_MT_POSITION_X x)
   (raw-event evdev/EV_ABS evdev/ABS_MT_POSITION_Y y)
   (raw-event evdev/EV_SYN evdev/SYN_REPORT 0)])

(defn- mt-up-frame
  []
  [(raw-event evdev/EV_ABS evdev/ABS_MT_TRACKING_ID -1)
   (raw-event evdev/EV_SYN evdev/SYN_REPORT 0)])

(defn- mt-tap
  [pos]
  (vec (concat (mt-down-frame pos)
               (mt-up-frame))))

(deftest standard-mt-tap-test
  (testing "standard MT protocol B emits touch down and up on SYN_REPORT"
    (is (= [{:kind :touch-down :pos [12 34]}
            {:kind :touch-up :pos [12 34]}]
           (strip-raw (:events (accept {:input-profile :none
                                        :viewport      [100 200]}
                                       (mt-tap [12 34]))))))))

(deftest coordinate-transform-test
  (testing "profiles transform touch coordinates against the rendered viewport"
    (let [down-pos (fn [profile]
                     (-> (accept {:input-profile profile
                                  :viewport      [100 200]}
                                 (mt-down-frame [10 20]))
                         :events
                         first
                         :pos))]
      (is (= {:none          [10 20]
              :switch-xy     [20 10]
              :kobo-default  [80 10]
              :kobo-mirror-y [20 190]}
             (into {}
                   (map (fn [profile]
                          [profile (down-pos profile)])
                        [:none :switch-xy :kobo-default :kobo-mirror-y])))))))

(deftest legacy-single-touch-tap-test
  (testing "legacy ABS_X/ABS_Y/ABS_PRESSURE emits the same tap events"
    (is (= [{:kind :touch-down :pos [12 34]}
            {:kind :touch-up :pos [12 34]}]
           (strip-raw (:events (accept {:input-profile :none
                                        :viewport      [100 200]}
                                       [(raw-event evdev/EV_ABS evdev/ABS_X 12)
                                        (raw-event evdev/EV_ABS evdev/ABS_Y 34)
                                        (raw-event evdev/EV_ABS evdev/ABS_PRESSURE 25)
                                        (raw-event evdev/EV_SYN evdev/SYN_REPORT 0)
                                        (raw-event evdev/EV_ABS evdev/ABS_PRESSURE 0)
                                        (raw-event evdev/EV_SYN evdev/SYN_REPORT 0)])))))))

(deftest kobo-mt-touch-major-zero-and-button-release-test
  (testing "Kobo MT frames with touch-major 0 stay active until touch button release"
    (is (= [{:kind :touch-down :pos [100 200]}
            {:kind :touch-move :pos [110 210]}
            {:kind :touch-up :pos [110 210]}]
           (strip-raw (:events (accept {:input-profile :none
                                        :viewport      [200 300]}
                                       [(raw-event evdev/EV_KEY evdev/BTN_TOUCH 1)
                                        (raw-event evdev/EV_KEY evdev/BTN_TOOL_FINGER 1)
                                        (raw-event evdev/EV_ABS evdev/ABS_MT_TRACKING_ID 0)
                                        (raw-event evdev/EV_ABS evdev/ABS_MT_POSITION_X 100)
                                        (raw-event evdev/EV_ABS evdev/ABS_MT_POSITION_Y 200)
                                        (raw-event evdev/EV_ABS evdev/ABS_MT_PRESSURE 31)
                                        (raw-event evdev/EV_ABS evdev/ABS_MT_TOUCH_MAJOR 0)
                                        (raw-event evdev/EV_SYN evdev/SYN_MT_REPORT 0)
                                        (raw-event evdev/EV_SYN evdev/SYN_REPORT 0)
                                        (raw-event evdev/EV_ABS evdev/ABS_MT_TRACKING_ID 0)
                                        (raw-event evdev/EV_ABS evdev/ABS_MT_POSITION_X 110)
                                        (raw-event evdev/EV_ABS evdev/ABS_MT_POSITION_Y 210)
                                        (raw-event evdev/EV_ABS evdev/ABS_MT_TOUCH_MAJOR 0)
                                        (raw-event evdev/EV_SYN evdev/SYN_MT_REPORT 0)
                                        (raw-event evdev/EV_SYN evdev/SYN_REPORT 0)
                                        (raw-event evdev/EV_KEY evdev/BTN_TOUCH 0)
                                        (raw-event evdev/EV_KEY evdev/BTN_TOOL_FINGER 0)
                                        (raw-event evdev/EV_SYN evdev/SYN_REPORT 0)])))))))

(deftest legacy-touch-tool-finger-tap-test
  (testing "legacy ABS_X/ABS_Y with BTN_TOOL_FINGER emits tap events"
    (is (= [{:kind :touch-down :pos [12 34]}
            {:kind :touch-up :pos [12 34]}]
           (strip-raw (:events (accept {:input-profile :none
                                        :viewport      [100 200]}
                                       [(raw-event evdev/EV_ABS evdev/ABS_X 12)
                                        (raw-event evdev/EV_ABS evdev/ABS_Y 34)
                                        (raw-event evdev/EV_KEY evdev/BTN_TOOL_FINGER 1)
                                        (raw-event evdev/EV_SYN evdev/SYN_REPORT 0)
                                        (raw-event evdev/EV_KEY evdev/BTN_TOOL_FINGER 0)
                                        (raw-event evdev/EV_SYN evdev/SYN_REPORT 0)])))))))

(deftest key-mapping-test
  (testing "known Kobo key codes emit normalized key events with decoded actions"
    (let [codes->keys     {193 :page-back
                           194 :page-forward
                           102 :home
                           116 :power
                           35  :sleep-cover
                           59  :sleep-cover
                           90  :light}
          values->actions {1 :press
                           0 :release
                           2 :repeat}
          raw-events      (vec (for [code  (keys codes->keys)
                                     value (keys values->actions)]
                                 (raw-event evdev/EV_KEY code value)))]
      (is (= (vec (for [[code key]     codes->keys
                        [value action] values->actions]
                    {:kind :key :key key :action action}))
             (strip-raw (:events (accept {:input-profile :none
                                          :viewport      [100 200]}
                                         raw-events)))))))
  (testing "unknown key codes are preserved for diagnostics"
    (is (= [{:kind :unknown-key :code 999 :action :press}]
           (strip-raw (:events (accept {:input-profile :none
                                        :viewport      [100 200]}
                                       [(raw-event evdev/EV_KEY 999 1)])))))))

(deftest syn-dropped-reset-test
  (testing "SYN_DROPPED emits a diagnostic event and resets active touch state"
    (let [after-down    (accept {:input-profile :none
                                 :viewport      [100 200]}
                                (mt-down-frame [12 34]))
          dropped       (kobo/accept-raw-events (:state after-down)
                                                [(raw-event evdev/EV_SYN evdev/SYN_DROPPED 0)])
          after-release (kobo/accept-raw-events (:state dropped)
                                                (mt-up-frame))]
      (is (= [{:kind :syn-dropped}]
             (strip-raw (:events dropped))))
      (is (= []
             (strip-raw (:events after-release)))))))
