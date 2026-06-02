(use ../deps/testament)
(import ../lib/signals :as sig)

(deftest cell-get-set-and-swap
  (def state (sig/cell 1))
  (is (= 1 (sig/get state)) "cell returns its initial value")
  (is (= 2 (sig/set state 2)) "set returns the new value")
  (is (= 2 (sig/get state)) "set replaces the cell value")
  (is (= 7 (sig/swap state + 5)) "swap returns the updated value")
  (is (= 7 (sig/get state)) "swap stores the updated value"))

(deftest computed-tracks-dependencies-and-caches-value
  (def n (sig/cell 2))
  (var runs 0)
  (def doubled
    (sig/computed
      (fn []
        (++ runs)
        (* 2 (sig/get n)))))
  (is (= 0 runs) "computed values are lazy before first read")
  (is (= 4 (sig/get doubled)) "computed reads derive from source cells")
  (is (= 1 runs) "first read computes once")
  (is (= 4 (sig/get doubled)) "clean computed values return cached values")
  (is (= 1 runs) "cached read does not recompute")
  (sig/set n 3)
  (is (= 1 runs) "source change marks computed dirty without eager recompute")
  (is (= 6 (sig/get doubled)) "dirty computed values recompute on read")
  (is (= 2 runs) "dirty computed recomputes exactly once"))

(deftest computed-replaces-stale-dynamic-dependencies
  (def use-left? (sig/cell true))
  (def left (sig/cell 10))
  (def right (sig/cell 20))
  (var runs 0)
  (def selected
    (sig/computed
      (fn []
        (++ runs)
        (if (sig/get use-left?)
          (sig/get left)
          (sig/get right)))))
  (is (= 10 (sig/get selected)) "initial branch reads the left source")
  (is (= 1 runs) "initial read computes once")
  (sig/set right 21)
  (is (= 10 (sig/get selected)) "inactive source changes do not dirty the computed value")
  (is (= 1 runs) "inactive source does not trigger recomputation")
  (sig/set use-left? false)
  (is (= 21 (sig/get selected)) "changing the branch switch recomputes using the right source")
  (is (= 2 runs) "branch switch triggers one recomputation")
  (sig/set left 11)
  (is (= 21 (sig/get selected)) "old branch source is unsubscribed")
  (is (= 2 runs) "old branch source does not trigger recomputation"))

(deftest effects-run-eagerly-on-signal-changes-and-can-be-disposed
  (def n (sig/cell 1))
  (def seen @[])
  (def eff
    (sig/effect [n]
                (fn []
                  (array/push seen (sig/get n)))))
  (is (deep= @[1] seen) "effect runs once when installed")
  (sig/set n 2)
  (is (deep= @[1 2] seen) "effect reruns after set")
  (sig/swap n + 3)
  (is (deep= @[1 2 5] seen) "effect reruns after swap")
  (sig/dispose eff)
  (sig/set n 8)
  (is (deep= @[1 2 5] seen) "disposed effects stop observing changes"))

(deftest lens-reads-and-updates-nested-state
  (def state
    (sig/cell
      @{:new-todo @{:text ""}
        :todos @[@{:completed? false}]}))
  (def text (sig/lens state [:new-todo :text]))
  (def completed? (sig/lens state [:todos 0 :completed?]))
  (def observed @[])
  (def eff
    (sig/effect [text]
                (fn []
                  (array/push observed (sig/get text)))))
  (is (= "" (sig/get text)) "lens reads table paths")
  (is (= false (sig/get completed?)) "lens reads through array indexes")
  (is (= "hello" (sig/set text "hello")) "lens set returns the nested value")
  (is (= "hello" (get (get (sig/get state) :new-todo) :text)) "lens set updates the parent cell")
  (is (deep= @["" "hello"] observed) "lens set notifies lens subscribers")
  (is (= true (sig/swap completed? not)) "lens swap returns the nested value")
  (is (= true (get (get (get (sig/get state) :todos) 0) :completed?)) "lens swap updates array paths")
  (sig/dispose eff))

(deftest get-records-render-dependencies-with-dynamic-binding
  (def n (sig/cell 1))
  (def doubled (sig/computed (fn [] (* 2 (sig/get n)))))
  (def deps @[])
  (with-dyns [:ui/deps deps]
    (sig/get n)
    (sig/get doubled))
  (is (= 2 (length deps)) "signal reads append to the current dependency collector")
  (is (= n (get deps 0)) "cell reads record the cell signal")
  (is (= doubled (get deps 1)) "computed reads record the computed signal, not its sources"))

(run-tests!)
