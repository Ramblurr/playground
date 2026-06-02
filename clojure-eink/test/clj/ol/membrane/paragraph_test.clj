(ns ol.membrane.paragraph-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [membrane.ui :as ui]
   [ol.membrane.paragraph :as paragraph]))

(deftest paragraph-api-constructs-backend-neutral-text-block-test
  (testing "paragraph stores text, font, width, and alignment without choosing a backend"
    (let [font      (ui/font "Noto Serif" 18)
          paragraph (paragraph/paragraph 123 font 240 {:align :left})]
      (is (= {:class    "ol.membrane.paragraph.Paragraph"
              :text     "123"
              :font     font
              :width    240.0
              :align    :left
              :origin   [0 0]
              :children nil}
             {:class    (.getName (class paragraph))
              :text     (:text paragraph)
              :font     (:font paragraph)
              :width    (:width paragraph)
              :align    (:align paragraph)
              :origin   (ui/origin paragraph)
              :children (ui/children paragraph)})))))

(deftest paragraph-api-defaults-to-left-aligned-default-font-test
  (testing "the short form is useful for simple fixed-width paragraphs"
    (let [paragraph (paragraph/paragraph "body" 120)]
      (is (= {:text  "body"
              :font  ui/default-font
              :width 120.0
              :align :left}
             (select-keys paragraph [:text :font :width :align]))))))
