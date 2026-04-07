(ns bench
  (:require
   [charred.api :as charred]
   [charred.coerce :as coerce]
   [clojure.data.json :as cdj]
   [com.knowclick.safe-js :as js]
   [criterium.bench :as crit]
   [criterium.util.helpers :as helpers])
  (:import
   [charred JSONWriter]
   [clojure.lang MapEntry]
   [com.knowclick.safe_js Unescaped]
   [java.util List Map Map$Entry]
   [java.util.function BiConsumer]))

#_(def profiler-iterations 200000)
#_(def criterium-limit-seconds 10)

(def p1 "console.log('foobar')")
(def p2
  {:foo "bar"
   :baz (js/! "5 + 6")})

(def payload p2)

(defn default-write-fn [x _out _options]
  (throw (ex-info "Don't know how to convert object to JSON."
                  {:object x
                   :class (class x)})))

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

(defn charred-object-writer [writer obj]
  (if (instance? Unescaped obj)
    (.write (.-w writer) (.toString obj))
    (default-object-writer writer obj)))

(def ^:private charred-writer
  ;; Work around the slash-escaping mismatch bug: charred defaults to `\/`
  ;; for strings like "</div>", while safe-js's data.json path emits `/`.
  (charred/write-json-fn {:escape-slash false
                          :obj-fn
                          (reify BiConsumer
                            (accept [_this writer value]
                              (charred-object-writer writer value)))}))

(defn charred-escape [x]
  (with-open [output (java.io.StringWriter.)]
    (charred-writer output x)
    (.toString output)))

(defn cdj-escape [x]
  (cdj/write-str x
                 {:indent           false
                  :escape-slash     false
                  :default-write-fn (fn [obj stream options]
                                      (if (instance? Unescaped obj)
                                        (.write stream (.toString obj))
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

(defn -main []
  (println "safe-js benchmark")
  #_(println "Criterium limit:" criterium-limit-seconds "seconds per benchmark")
  (println)
  (println "charred")
  (crit/bench (charred-escape payload))
  (println)
  (let [charred-result {:label   "charred"
                        :mean-ns (latest-mean-ns)}]
    (println "clojure.data.json")
    (crit/bench (cdj-escape payload))
    (print-summary charred-result
                   {:label "clojure.data.json" :mean-ns (latest-mean-ns)})))

(-main)
