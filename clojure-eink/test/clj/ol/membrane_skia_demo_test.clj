(ns ol.membrane-skia-demo-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [membrane.ui :as ui]
   [ol.membrane.skia-eink-backend :as backend]))

(defn- skia-native-lib
  []
  (not-empty (System/getenv "EINK_SKIA_NATIVE_LIB")))

(defn- font-dir
  []
  (not-empty (System/getenv "EINK_FONT_DIR")))

(defn- resolve-demo-var
  [sym]
  (try
    (requiring-resolve sym)
    (catch java.io.FileNotFoundException _
      nil)))

(defn- all-nodes
  [elem]
  (tree-seq #(seq (ui/children %)) ui/children elem))

(defn- label-texts
  [elem]
  (->> (all-nodes elem)
       (keep (fn [node]
               (when (instance? membrane.ui.Label node)
                 (:text node))))
       set))

(defn- paragraph-node?
  [node]
  (= "ol.membrane.skia_eink_backend.Paragraph" (.getName (class node))))

(defn- dark-byte?
  [b]
  (< (bit-and 0xFF b) 250))

(deftest skia-demo-ui-structure-test
  (testing "Skia demo builds a Membrane value with text proof content"
    (let [demo-ui-var (resolve-demo-var 'ol.membrane-skia-demo/demo-ui)]
      (is (some? demo-ui-var) "ol.membrane-skia-demo/demo-ui should exist")
      (when demo-ui-var
        (let [elem (@demo-ui-var {:width 600 :height 420})]
          (is (= {:bounds          [600 420]
                  :title?          true
                  :rounded-action? true
                  :unicode-smoke?  true
                  :paragraph?      true}
                 {:bounds          (ui/bounds elem)
                  :title?          (contains? (label-texts elem) "Skia Membrane FBInk")
                  :rounded-action? (contains? (label-texts elem) "Skia render path")
                  :unicode-smoke?  (contains? (label-texts elem) "Unicode smoke: Café — Ω")
                  :paragraph?      (boolean (some paragraph-node? (all-nodes elem)))})))))))

(deftest skia-demo-renders-through-skia-backend-test
  (testing "Skia demo renders through the Skia backend into non-white gray8 output"
    (if-let [native-lib (skia-native-lib)]
      (if-let [font-dir (font-dir)]
        (let [demo-view-var (resolve-demo-var 'ol.membrane-skia-demo/demo-view)]
          (is (some? demo-view-var) "ol.membrane-skia-demo/demo-view should exist")
          (when demo-view-var
            (let [context (backend/open-context! {:native-lib     native-lib
                                                  :font-dir       font-dir
                                                  :default-family "Noto Sans"
                                                  :width          240
                                                  :height         160})]
              (try
                (let [{:keys [gray]} (backend/render-view! context
                                                           @demo-view-var
                                                           {:include-container-info true})]
                  (is (= {:width  240
                          :height 160
                          :stride 240}
                         (select-keys gray [:width :height :stride])))
                  (is (some dark-byte? (:data gray)))
                  (is (= 1 @(:render-count context))))
                (finally
                  (backend/close-context! context))))))
        (is true "skipped: EINK_FONT_DIR is absent"))
      (is true "skipped: EINK_SKIA_NATIVE_LIB is absent"))))
