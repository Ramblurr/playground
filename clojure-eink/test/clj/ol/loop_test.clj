(ns ol.loop-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [ol.loop :as loop]))

(deftest parse-command-line-test
  (testing "blank and simple loop commands"
    (is (= {:command :blank :args []}
           (loop/parse-command-line "   ")))
    (is (= {:command :reload :args []}
           (loop/parse-command-line "reload")))
    (is (= {:command :quit :args []}
           (loop/parse-command-line "quit"))))
  (testing "render commands retain option tokens"
    (is (= {:command :render
            :args    ["--renders" "2" "--render-mode" "cached-layout"]}
           (loop/parse-command-line "render --renders 2 --render-mode cached-layout")))))
