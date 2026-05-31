(ns ol.project-input-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [ol.project :as project]))

(deftest input-event-layout-size-test
  (testing "Clojure FFM layout matches the fixed native input event record"
    (is (= 40 (project/input-event-layout-size)))))

(deftest native-input-event-size-test
  (testing "native bridge reports the same fixed input event size when available"
    (if-let [native-lib (System/getenv "EINK_NATIVE_LIB")]
      (let [native (project/load-native native-lib)]
        (is (= 40 (project/input-event-size native))))
      (is true "EINK_NATIVE_LIB not set; skipping native input size assertion"))))
