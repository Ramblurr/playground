(ns ol.bench.reading-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [membrane.ui :as ui]
   [ol.bench.reading :as reading]
   [ol.bench.reading-benchmark :as reading-benchmark]
   [ol.membrane.backend.java2d]
   [ol.membrane.paragraph]))

(defn- all-nodes
  [elem]
  (tree-seq #(seq (ui/children %)) ui/children elem))

(deftest reading-screen-uses-paragraph-elements-not-word-labels-test
  (testing "the production-like reading screen uses paragraph text blocks, not one label per word"
    (let [elem            (reading/reading-screen {:container-size [1264 1680]})
          nodes           (all-nodes elem)
          paragraph-texts (->> nodes
                               (keep (fn [node]
                                       (when (instance? ol.membrane.paragraph.Paragraph node)
                                         (:text node))))
                               vec)
          label-texts     (->> nodes
                               (keep (fn [node]
                                       (when (instance? membrane.ui.Label node)
                                         (:text node))))
                               vec)]
      (is (= {:bounds          [1264 1680]
              :paragraph-count (count reading/chapter-text)
              :paragraph-texts reading/chapter-text
              :labels          ["Chapter 7" "247 · The quiet renderer"]}
             {:bounds          (ui/bounds elem)
              :paragraph-count (count paragraph-texts)
              :paragraph-texts paragraph-texts
              :labels          label-texts})))))

(deftest reading-benchmark-documents-measurement-scope-test
  (testing "benchmark output has an explicit scope for interpreting timings"
    (is (= {:total-ms "wall time around render-view!"
            :includes [:view/layout :backend-render :gray-copy]
            :excludes [:framebuffer-refresh]
            :present? false}
           (reading-benchmark/measurement-scope {:present? false})))))
