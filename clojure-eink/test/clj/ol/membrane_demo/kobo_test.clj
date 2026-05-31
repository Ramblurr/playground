(ns ol.membrane-demo.kobo-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [membrane.component :as component]
   [membrane.ui :as ui]
   [ol.membrane-demo.kobo :as kobo]
   [ol.membrane.eink-backend :as backend]
   [ol.project :as project]))

(defn- all-nodes
  [elem]
  (tree-seq #(seq (ui/children %)) ui/children elem))

(defn- labels
  [elem]
  (->> (all-nodes elem)
       (keep (fn [node]
               (when (instance? membrane.ui.Label node)
                 (:text node))))
       frequencies))

(deftest default-more-state-test
  (testing "keeps the More screen state explicit and serializable"
    (is (= {:time "2:58 PM"
            :menu ["My Wishlist"
                   "My Articles"
                   "Activity"
                   "Beta Features"
                   "Settings"
                   "Help"]
            :tabs ["Home" "My Books" "Discover" "More"]
            :active-tabs [:more]}
           {:time (:time kobo/default-more-state)
            :menu (mapv :label (:menu kobo/default-more-state))
            :tabs (mapv :label (:tabs kobo/default-more-state))
            :active-tabs (mapv :id (filter :active? (:tabs kobo/default-more-state)))}))))

(deftest layout-scales-from-container-test
  (testing "layout is derived from the viewport rather than fixed to one device size"
    (is (= {:screen [500 675]
            :margin-x 25.0
            :status-h 45.0
            :header-h 50.0
            :row-h 55.0
            :bottom-h 52.5
            :tab-count 4}
           (select-keys (kobo/layout-for [500 675])
                        [:screen :margin-x :status-h :header-h :row-h :bottom-h :tab-count])))))

(deftest theme-scales-typography-from-container-test
  (testing "font sizes derive from viewport scale instead of fixed reference pixels"
    (is (= {:reference {:status 20.0
                        :title 46.0
                        :menu 29.0
                        :tab 24.0}
            :small {:status 8.0
                    :title 18.4
                    :menu 11.6
                    :tab 9.6}}
           {:reference (-> (kobo/theme-for [1000 1350])
                            :fonts
                            (select-keys [:status :title :menu :tab])
                            (update-vals :size))
            :small (-> (kobo/theme-for [400 540])
                       :fonts
                       (select-keys [:status :title :menu :tab])
                       (update-vals :size))}))))

(deftest more-screen-component-tree-test
  (testing "component app renders the expected Kobo More labels"
    (let [view (component/make-app #'kobo/more-screen
                                   (assoc kobo/default-more-state :viewport [400 540]))
          elem (view)]
      (is (= [400 540] (ui/bounds elem)))
      (is (= {"2:58 PM" 1
              "More" 2
              "My Wishlist" 1
              "My Articles" 1
              "Activity" 1
              "Beta Features" 1
              "Settings" 1
              "Help" 1
              "Home" 1
              "My Books" 1
              "Discover" 1}
             (select-keys (labels elem)
                          ["2:58 PM" "More" "My Wishlist" "My Articles" "Activity"
                           "Beta Features" "Settings" "Help" "Home" "My Books" "Discover"]))))))

(deftest more-screen-renders-through-eink-backend-test
  (testing "Kobo More component renders through the Java2D e-ink backend"
    (let [view    (component/make-app #'kobo/more-screen
                                      (assoc kobo/default-more-state :viewport [400 540]))
          context (backend/open-context! {:width 400 :height 540})]
      (try
        (let [{:keys [image]} (backend/render-view! context view {})
              gray            (project/image->gray8 image)]
          (is (= {:width 400 :height 540}
                 (select-keys gray [:width :height])))
          (is (some #(< (bit-and 0xFF %) 240) (:data gray))))
        (finally
          (backend/close-context! context))))))
