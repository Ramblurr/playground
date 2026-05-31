(ns ol.membrane.component-smoke-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [membrane.basic-components :as basic]
   [membrane.component :as component :refer [defui]]
   [membrane.ui :as ui]
   [ol.membrane.backend.java2d :as backend]
   [ol.project :as project]))

(defui hello-component [{:keys [text]}]
  (ui/label text (ui/font nil 24)))

(deftest basic-components-load-test
  (testing "vendored membrane.basic-components can be required"
    (is (var? #'basic/button))))

(deftest defui-renders-through-eink-backend-test
  (testing "a Membrane defui component renders through the e-ink backend"
    (let [view    (component/make-app #'hello-component {:text "Hello"})
          context (backend/open-context! {:width 200 :height 100})]
      (try
        (let [{:keys [image]} (backend/render-view! context view {})
              gray            (project/image->gray8 image)]
          (is (= {:width 200 :height 100}
                 (select-keys gray [:width :height])))
          (is (some #(< (bit-and 0xFF %) 250) (:data gray))))
        (finally
          (backend/close-context! context))))))
