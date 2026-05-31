(ns ol.membrane-demo-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [membrane.ui :as ui]
   [ol.membrane-demo :as demo]
   [ol.membrane.eink-backend :as backend]
   [ol.project :as project]))

(defn- gray-at
  [gray x y]
  (bit-and 0xFF (aget ^bytes (:data gray) (+ x (* y (:stride gray))))))

(defn- all-nodes
  [elem]
  (tree-seq #(seq (ui/children %)) ui/children elem))

(defn- label-translate
  [elem text]
  (some (fn [node]
          (when (and (instance? membrane.ui.Translate node)
                     (instance? membrane.ui.Label (:drawable node))
                     (= text (:text (:drawable node))))
            node))
        (all-nodes elem)))

(defn- label-texts
  [elem]
  (->> (all-nodes elem)
       (keep (fn [node]
               (when (instance? membrane.ui.Label node)
                 (:text node))))
       set))

(defn- near?
  [expected actual]
  (< (abs (- expected actual)) 0.5))

(deftest demo-ui-test
  (testing "provides a normal-polarity button-like Membrane demo"
    (let [elem              (demo/demo-ui {:width 640 :height 480})
          image             (backend/render-to-image! elem {:width 640 :height 480})
          gray              (project/image->gray8 image)
          click-translate   (label-translate elem "Click Me")
          [label-w label-h] (backend/text-bounds (ui/font nil 28) "Click Me")]
      (is (= [640 480] (ui/bounds elem)))
      (is (some? click-translate))
      (is (near? (/ (- 360 label-w) 2.0) (:x click-translate)))
      (is (near? (/ (- 82 label-h) 2.0) (:y click-translate)))
      (is (> (gray-at gray 10 10) 240) "background should be white")
      (is (some #(< (bit-and 0xFF %) 250) (:data gray))))))

(deftest kobo-more-view-option-test
  (testing "demo runner can select the component-based Kobo More screen"
    (let [view    (demo/view-for-options {:kobo-more? true})
          context (backend/open-context! {:width 400 :height 540})]
      (try
        (let [{:keys [image]} (backend/render-view! context view {:include-container-info true})
              gray            (project/image->gray8 image)
              elem            (view {:container-size [400 540]})]
          (is (= {:bounds [400 540]
                  :has-more-title? true
                  :has-wishlist? true
                  :dark-pixels? true}
                 {:bounds (ui/bounds elem)
                  :has-more-title? (contains? (label-texts elem) "More")
                  :has-wishlist? (contains? (label-texts elem) "My Wishlist")
                  :dark-pixels? (boolean (some #(< (bit-and 0xFF %) 240) (:data gray)))})))
        (finally
          (backend/close-context! context))))))
