(ns ol.input.runtime-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [ol.input.runtime :as runtime])
  (:import
   [java.util.concurrent TimeUnit]))

(deftest input-thread-enqueues-non-empty-batches-test
  (testing "polling runs on a background thread and enqueues only non-empty batches"
    (let [opened? (atom false)
          closed  (atom 0)
          calls   (atom 0)
          handle  (runtime/start-input-thread!
                   nil
                   {:open-fn    (fn [] (reset! opened? true) 1)
                    :close-fn   (fn [] (swap! closed inc))
                    :poll-fn    (fn []
                                  (case (swap! calls inc)
                                    1 []
                                    [{:type 1 :code 193 :value 1}]))
                    :timeout-ms 1})]
      (try
        (is (= [{:type 1 :code 193 :value 1}]
               (.poll (:queue handle) 1 TimeUnit/SECONDS)))
        (is (true? @opened?))
        (finally
          (runtime/stop-input-thread! handle)))
      (is (= 1 @closed)))))

(deftest input-thread-enqueues-errors-test
  (testing "poll exceptions are reported through the queue instead of silently killing the thread"
    (let [closed (atom 0)
          handle (runtime/start-input-thread!
                  nil
                  {:open-fn    (fn [] 1)
                   :close-fn   (fn [] (swap! closed inc))
                   :poll-fn    (fn [] (throw (ex-info "poll failed" {:code -5})))
                   :timeout-ms 1})]
      (try
        (let [error-record (.poll (:queue handle) 1 TimeUnit/SECONDS)]
          (is (= {:kind    :input-error
                  :message "poll failed"}
                 (select-keys error-record [:kind :message])))
          (is (= {:code -5} (ex-data (:error error-record)))))
        (finally
          (runtime/stop-input-thread! handle)))
      (is (= 1 @closed)))))

(deftest drain-queue-test
  (testing "drains all currently available queue items without blocking"
    (let [queue (java.util.concurrent.LinkedBlockingQueue.)]
      (.put queue [:a])
      (.put queue [:b])
      (is (= [[:a] [:b]]
             (runtime/drain-queue! queue)))
      (is (= []
             (runtime/drain-queue! queue))))))
