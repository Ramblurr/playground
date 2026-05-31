(ns ol.membrane.backend.java2d-input-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [membrane.component :as component :refer [defui]]
   [membrane.ui :as ui]
   [ol.membrane.backend.java2d :as backend]))

(defui input-probe [{:keys [last-event]}]
  (ui/on :mouse-down (fn [_pos]
                       [[:set $last-event :mouse-down]])
         :mouse-up (fn [_pos]
                     [[:set $last-event :mouse-up]])
         :key-press (fn [key]
                      [[:set $last-event key]])
         (ui/fixed-bounds [100 80]
                          [(ui/rectangle 100 80)
                           (ui/label (name (or last-event :none)))])))

(deftest dispatch-touch-events-test
  (testing "normalized touch events dispatch through Membrane mouse handlers"
    (let [state (atom {:last-event :none})
          view  (component/make-app #'input-probe state)
          elem  (view)]
      (backend/dispatch-normalized-event! elem {:kind :touch-down :pos [10 20]})
      (is (= :mouse-down (:last-event @state)))
      (backend/dispatch-normalized-event! (view) {:kind :touch-up :pos [10 20]})
      (is (= :mouse-up (:last-event @state))))))

(deftest dispatch-key-events-test
  (testing "known normalized key presses dispatch through Membrane key handlers"
    (let [state (atom {:last-event :none})
          view  (component/make-app #'input-probe state)]
      (backend/dispatch-normalized-event! (view) {:kind   :key
                                                  :key    :page-forward
                                                  :action :press})
      (is (= :page-forward (:last-event @state)))
      (backend/dispatch-normalized-event! (view) {:kind   :key
                                                  :key    :page-back
                                                  :action :repeat})
      (is (= :page-back (:last-event @state)))
      (backend/dispatch-normalized-event! (view) {:kind   :key
                                                  :key    :home
                                                  :action :release})
      (is (= :page-back (:last-event @state))))))

(deftest dispatch-normalized-events-test
  (testing "dispatches a batch in order"
    (let [state (atom {:last-event :none})
          view  (component/make-app #'input-probe state)]
      (backend/dispatch-normalized-events! (view)
                                           [{:kind :touch-down :pos [10 20]}
                                            {:kind :key :key :home :action :press}])
      (is (= :home (:last-event @state))))))
