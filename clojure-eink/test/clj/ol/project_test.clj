(ns ol.project-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [ol.project :as project]))

(deftest render-demo-image-test
  (testing "renders grayscale text into a byte-backed image"
    (let [image (project/render-demo-image {:width  320
                                            :height 240
                                            :text   "Hello Kobo"})
          gray  (project/image->gray8 image)]
      (is (= 320 (:width gray)))
      (is (= 240 (:height gray)))
      (is (= 320 (:stride gray)))
      (is (= (* 320 240) (alength ^bytes (:data gray))))
      (is (some #(< (bit-and 0xFF %) 250) (:data gray))))))

(deftest parse-benchmark-options-test
  (testing "renders/repeat aliases and present mode flags"
    (let [parsed (try
                   (select-keys (project/parse-args ["--renders" "5" "--no-present"])
                                [:renders :present-mode :native?])
                   (catch Exception e
                     {:error (.getMessage e)}))]
      (is (= {:renders      5
              :present-mode :none
              :native?      false}
             parsed)))
    (let [parsed (try
                   (select-keys (project/parse-args ["--present" "--repeat" "3" "--present-last"])
                                [:renders :present-mode :native?])
                   (catch Exception e
                     {:error (.getMessage e)}))]
      (is (= {:renders      3
              :present-mode :last
              :native?      true}
             parsed)))
    (let [parsed (try
                   (select-keys (project/parse-args ["--present" "--renders" "5" "--no-present"])
                                [:renders :present-mode :native?])
                   (catch Exception e
                     {:error (.getMessage e)}))]
      (is (= {:renders      5
              :present-mode :none
              :native?      true}
             parsed)))))

(deftest parse-args-with-initial-options-test
  (testing "command-loop style parsing preserves unspecified base options"
    (let [base   (project/parse-args ["--present" "--render-mode" "cached-layout" "--no-wait"])
          parsed (project/parse-args base ["--renders" "2" "--present-last"])]
      (is (= 2 (:renders parsed)))
      (is (= :last (:present-mode parsed)))
      (is (= :cached-layout (:render-mode parsed)))
      (is (false? (:wait? parsed)))
      (is (true? (:native? parsed))))))

(deftest parse-render-mode-test
  (testing "render mode benchmark variants"
    (is (= :layout (:render-mode (project/parse-args []))))
    (is (= :cached-layout (:render-mode (project/parse-args ["--render-mode" "cached-layout"]))))
    (is (= :simple-text (:render-mode (project/parse-args ["--mode" "simple-text"]))))
    (is (= :rects (:render-mode (project/parse-args ["--render-mode" "rects"]))))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"unknown render mode"
                          (project/parse-args ["--render-mode" "bogus"])))))

(deftest render-demo-frame-timings-test
  (testing "render-demo-frame returns an image and per-phase timings"
    (let [render-frame (some-> (ns-resolve 'ol.project 'render-demo-frame) deref)]
      (is (fn? render-frame))
      (when render-frame
        (let [{:keys [image timings]} (render-frame {:width  320
                                                     :height 240
                                                     :text   "Hello Kobo"})]
          (is (= 320 (.getWidth image)))
          (is (= 240 (.getHeight image)))
          (doseq [phase [:image-allocation :background-fill :text-layout :glyph-draw]]
            (is (contains? timings phase))
            (is (number? (get timings phase)))))))))