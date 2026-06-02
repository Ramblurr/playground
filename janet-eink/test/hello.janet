(use ../deps/testament)

(deftest one-plus-one
  (is (= 2 (+ 1 1)) "1 + 1 = 2"))

(run-tests!)
