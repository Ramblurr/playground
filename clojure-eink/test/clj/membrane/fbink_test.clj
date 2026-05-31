(ns membrane.fbink-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [membrane.fbink :as fbink]
   [membrane.ui :as ui]
   [ol.project :as project]))

(deftest draw-basic-ui-to-gray-image-test
  (testing "renders Membrane shapes and text to a byte-backed grayscale image"
    (let [elem  [(ui/with-color [0 0 0]
                   (ui/rectangle 80 40))
                 (ui/translate 12 28
                               (ui/label "Hi" (ui/font nil 24)))]
          image (fbink/render-to-image! elem {:width 160 :height 96})
          gray  (project/image->gray8 image)]
      (is (= 160 (:width gray)))
      (is (= 96 (:height gray)))
      (is (some #(< (bit-and 0xFF %) 250) (:data gray))))))

(deftest demo-ui-test
  (testing "provides a basic button-like Membrane demo"
    (let [elem  (fbink/demo-ui {:width 320 :height 240})
          image (fbink/render-to-image! elem {:width 320 :height 240})
          gray  (project/image->gray8 image)]
      (is (= [320 240] (ui/bounds elem)))
      (is (some #(< (bit-and 0xFF %) 250) (:data gray))))))
