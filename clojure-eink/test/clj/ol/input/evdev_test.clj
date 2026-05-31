(ns ol.input.evdev-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [ol.input.evdev :as evdev]))

(deftest annotate-event-test
  (testing "adds symbolic tags for raw evdev type and code numbers"
    (is (= {:type      evdev/EV_ABS
            :code      evdev/ABS_MT_POSITION_X
            :value     522
            :type-name :ev/abs
            :code-name :abs-mt/position-x}
           (evdev/annotate-event {:type  evdev/EV_ABS
                                  :code  evdev/ABS_MT_POSITION_X
                                  :value 522})))))
