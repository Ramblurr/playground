(ns ol.membrane-demo-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [membrane.ui :as ui]
   [ol.membrane-demo :as demo]
   [ol.membrane-demo.kobo :as kobo]
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
          (is (= {:bounds          [400 540]
                  :has-more-title? true
                  :has-wishlist?   true
                  :dark-pixels?    true}
                 {:bounds          (ui/bounds elem)
                  :has-more-title? (contains? (label-texts elem) "More")
                  :has-wishlist?   (contains? (label-texts elem) "My Wishlist")
                  :dark-pixels?    (boolean (some #(< (bit-and 0xFF %) 240) (:data gray)))})))
        (finally
          (backend/close-context! context))))))

(deftest kobo-more-view-preserves-interactive-state-test
  (testing "state updated by Membrane input dispatch survives the next view render"
    (let [viewport [400 540]
          layout   (kobo/layout-for viewport)
          menu-top (+ (:status-h layout) (:header-h layout))
          row-h    (:row-h layout)
          sample-y (fn [row-idx]
                     (int (+ menu-top (* row-idx row-h) 10)))
          active?  (fn [elem row-idx]
                     (let [image (backend/render-to-image! elem {:width 400 :height 540})
                           gray  (project/image->gray8 image)]
                       (< (gray-at gray 1 (sample-y row-idx)) 64)))
          view     (demo/view-for-options {:kobo-more? true})
          before   (view {:container-size viewport})]
      (backend/dispatch-normalized-event! before {:kind   :key
                                                  :key    :page-forward
                                                  :action :press})
      (let [after (view {:container-size viewport})]
        (is (= {:articles-before? true
                :activity-before? false
                :articles-after?  false
                :activity-after?  true}
               {:articles-before? (active? before 1)
                :activity-before? (active? before 2)
                :articles-after?  (active? after 1)
                :activity-after?  (active? after 2)}))))))

(deftest input-runner-flags-test
  (testing "membrane demo parses input flags before delegating render flags"
    (is (= {:runner       {:loop?               false
                           :kobo-more?          true
                           :input?              true
                           :input-dump?         true
                           :input-raw-dump?     true
                           :input-grab?         true
                           :input-profile       :none
                           :input-render-moves? true
                           :verbose-input?      true}
            :project-args ["--no-wait" "--width" "400"]}
           (let [{:keys [runner-opts project-args]}
                 (demo/parse-runner-args ["--more"
                                          "--input"
                                          "--input-dump"
                                          "--input-raw-dump"
                                          "--input-grab"
                                          "--input-profile" "none"
                                          "--input-render-moves"
                                          "--verbose-input"
                                          "--no-wait"
                                          "--width" "400"])]
             {:runner       (select-keys runner-opts [:loop? :kobo-more? :input? :input-dump?
                                                      :input-raw-dump? :input-grab? :input-profile
                                                      :input-render-moves? :verbose-input?])
              :project-args project-args})))))

(deftest input-profile-validation-test
  (testing "input profile values are validated while parsing runner options"
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"unknown Kobo input profile"
                          (demo/parse-runner-args ["--input-profile" "bogus"])))))

(deftest input-options-imply-native-present-test
  (testing "--input implies native presentation unless --no-present is explicit"
    (is (= {:native? true :present? true :present-mode :each}
           (select-keys (demo/options-for-args ["--input"])
                        [:native? :present? :present-mode])))
    (is (= {:native? true :present? false :present-mode :none}
           (select-keys (demo/options-for-args ["--input" "--no-present"])
                        [:native? :present? :present-mode])))))