(ns ol.input.runtime
  (:require
   [ol.project :as project])
  (:import
   [java.util.concurrent LinkedBlockingQueue TimeUnit]))

(defn drain-queue!
  [^LinkedBlockingQueue queue]
  (loop [items []]
    (if-let [item (.poll queue)]
      (recur (conj items item))
      items)))

(defn- default-open-fn
  [native opts]
  (fn []
    (project/input-open-scan! native (select-keys opts [:grab? :verbose?]))))

(defn- default-poll-fn
  [native {:keys [capacity timeout-ms]}]
  (fn []
    (project/input-poll! native {:capacity   capacity
                                 :timeout-ms timeout-ms})))

(defn- default-close-fn
  [native]
  (fn []
    (project/input-close! native)))

(defn- error-record
  [^Throwable error]
  {:kind    :input-error
   :message (.getMessage error)
   :error   error})

(defn start-input-thread!
  [native {:keys [queue open-fn poll-fn close-fn capacity timeout-ms thread-name join-timeout-ms]
           :or   {capacity        256
                  timeout-ms      250
                  thread-name     "eink-input-poll"
                  join-timeout-ms 1000}
           :as   opts}]
  (let [queue    (or queue (LinkedBlockingQueue.))
        running? (atom true)
        opened?  (volatile! false)
        open-fn  (or open-fn (default-open-fn native opts))
        poll-fn  (or poll-fn (default-poll-fn native {:capacity capacity :timeout-ms timeout-ms}))
        close-fn (or close-fn (default-close-fn native))
        thread   (Thread.
                  (fn []
                    (try
                      (open-fn)
                      (vreset! opened? true)
                      (while @running?
                        (try
                          (let [batch (poll-fn)]
                            (when (seq batch)
                              (.put queue batch)))
                          (catch Throwable t
                            (.put queue (error-record t))
                            (reset! running? false))))
                      (catch Throwable t
                        (.put queue (error-record t))
                        (reset! running? false))
                      (finally
                        (when @opened?
                          (close-fn)))))
                  thread-name)]
    (.setDaemon thread true)
    (.start thread)
    {:native          native
     :queue           queue
     :running?        running?
     :thread          thread
     :join-timeout-ms join-timeout-ms}))

(defn stop-input-thread!
  [{:keys [running? ^Thread thread join-timeout-ms]}]
  (when running?
    (reset! running? false))
  (when thread
    (.join thread (long (or join-timeout-ms 1000))))
  nil)
