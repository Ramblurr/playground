(ns bench
  (:require
   [charred.api :as charred]
   [charred.coerce :as coerce]
   [clj-async-profiler.core :as prof]
   [clojure.data.json :as cdj]
   [clojure.java.io :as io]
   [com.knowclick.safe-js :as js]
   [criterium.agent :as agent]
   [criterium.bench :as crit]
   [criterium.util.helpers :as helpers])
  (:import
   [charred JSONWriter]
   [clojure.lang MapEntry]
   [com.knowclick.safe_js Unescaped]
   [java.io File StringWriter Writer]
   [java.util List Map Map$Entry]
   [java.util.function BiConsumer]))

(set! *warn-on-reflection* true)

(def profiler-iterations 200000)

(def p1 "console.log('foobar')")
(def p2
  {:foo "bar"
   :baz (js/! "5 + 6")})

(def payload p2)

(defn default-write-fn [x _out _options]
  (throw (ex-info "Don't know how to convert object to JSON."
                  {:object x
                   :class (class x)})))

;; added typehints to remove reflection warnings
(defn default-object-writer [^JSONWriter w value]
  (let [value (when-not (nil? value) (charred/->json-data value))]
    (cond
      (or (sequential? value)
          (instance? List value)
          (.isArray (.getClass ^Object value)))
      (.writeArray w (coerce/->iterator value))
      (instance? Map value)
      (.writeMap w (coerce/map-iter (fn [^Map$Entry e]
                                      (MapEntry. (charred/->json-data (.getKey e))
                                                 (.getValue e)))
                                    (.entrySet ^Map value)))
      :else
      (.writeObject w value))))

;; added typehints to remove reflection warnings
(defn charred-object-writer [^JSONWriter writer obj]
  (if (instance? Unescaped obj)
    (let [^Writer w (.-w writer)
          ^Object obj obj]
      (.write w (.toString obj)))
    (default-object-writer writer obj)))

#_(def charred-writer
  ;; Work around the slash-escaping mismatch bug: charred defaults to `\/`
  ;; for strings like "</div>", while safe-js's data.json path emits `/`.
    (charred/write-json-fn {:escape-slash false
                            :obj-fn
                            (reify BiConsumer
                              (accept [_this writer value]
                                (charred-object-writer writer value)))}))

#_(def ^StringWriter charred-output (StringWriter.))

#_(defn charred-escape [x]
    #_(with-open [output (StringWriter.)]
        (charred-writer output x)
        (.toString output))
    (let [^StringWriter output charred-output]
      (.setLength (.getBuffer output) 0)
      (charred-writer output x)
      (.toString output)))

(def charred-obj-fn
  (reify BiConsumer
    (accept [_ writer value]
      (charred-object-writer writer value))))

;; this constructs JSONWriter directly over the per-call StringWriter instead of
;; going through charred/write-json-fn, which still calls clojure.java.io/writer
;; on every invocation. That removes clojure.java.io/writer protocol-dispatch overhead
(defn- charred-escape [x]
  (let [output (StringWriter.)
        writer (JSONWriter.
                output
                true
                false
                true
                nil
                charred-obj-fn)]
    (.writeObject writer x)
    (.toString output)))

(defn cdj-escape [x]
  (cdj/write-str x
                 {:indent           false
                  :escape-slash     false
                  :default-write-fn (fn [obj ^Writer stream options]
                                      (if (instance? Unescaped obj)
                                        (let [^Object obj obj]
                                          (.write stream (.toString obj)))
                                        (default-write-fn obj stream options)))}))

(defn latest-mean-ns []
  (helpers/stats-value (:data (crit/last-bench))
                       :stats
                       :elapsed-time
                       :mean))

(defn print-summary [charred-result data-json-result]
  (let [ratio        (/ (:mean-ns charred-result) (:mean-ns data-json-result))
        winner       (if (< ratio 1.0) "charred" "clojure.data.json")
        slower-ratio (if (< ratio 1.0) (/ 1.0 ratio) ratio)]
    (println)
    (println (format "Winner: %s (%.2fx faster by criterium mean elapsed time)"
                     winner
                     slower-ratio))))

(defn result-path [result]
  (.getAbsolutePath ^File (io/file result)))

(defn run-profile! [label benchmark-fn]
  (println)
  (println (format "%s profiler (%d iterations)" label profiler-iterations))
  (prof/start {})
  (dotimes [_ profiler-iterations]
    (benchmark-fn))
  (println (format "%s profiler result: %s" label (result-path (prof/stop {})))))

(defn -main [& _args]
  #_(println (js/str payload))
  (println "Criterium agent loaded:" (agent/loaded?))
  #_(println "Criterium limit:" criterium-limit-seconds "seconds per benchmark")
  (println)
  (println "charred")
  (crit/bench (charred-escape payload))
  (let [charred-result {:label         "charred"
                        :mean-ns (latest-mean-ns)}]
    (run-profile! "charred" #(charred-escape payload))
    (println)
    (println "clojure.data.json")
    (crit/bench (cdj-escape payload))
    (let [data-json-result {:label         "clojure.data.json"
                            :mean-ns (latest-mean-ns)}]
      (run-profile! "clojure.data.json" #(cdj-escape payload))
      (print-summary charred-result data-json-result))))
