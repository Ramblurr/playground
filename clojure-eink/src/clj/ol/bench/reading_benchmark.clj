(ns ol.bench.reading-benchmark
  (:require
   [clojure.string :as str]
   [ol.bench.reading :as reading]))

(def default-renders 10)

(def scenarios
  {"reading-skia"            {:backend :skia :batch-text? false}
   "reading-skia-batch-text" {:backend :skia :batch-text? true}
   "reading-java2d"          {:backend :java2d}})

(defn nanos []
  (System/nanoTime))

(defn elapsed-ms
  [start]
  (/ (double (- (nanos) start)) 1000000.0))

(defn timed
  [f]
  (let [start (nanos)
        ret   (f)]
    [ret (elapsed-ms start)]))

(defn avg
  [xs]
  (if (seq xs)
    (/ (reduce + 0.0 xs) (count xs))
    0.0))

(defn summary
  [label rows]
  (let [totals (mapv :total-ms rows)]
    {:label   label
     :first   (first totals)
     :min     (when (seq totals) (apply min totals))
     :avg-all (avg totals)
     :avg-2-n (avg (subvec totals (min 1 (count totals))))
     :avg-3-n (avg (subvec totals (min 2 (count totals))))
     :last    (last totals)}))

(defn delta-stats
  [before after]
  (when (and before after)
    (into {}
          (for [k [:entries :hits :misses :evictions]]
            [k (- (long (get after k 0))
                  (long (get before k 0)))]))))

(defn measurement-scope
  [{:keys [present?]}]
  (let [present? (boolean present?)]
    {:total-ms "wall time around render-view!"
     :includes (cond-> [:view/layout :backend-render :gray-copy]
                 present? (conj :framebuffer-refresh))
     :excludes (if present? [] [:framebuffer-refresh])
     :present? present?}))

(defn- reading-view
  [container-info]
  (reading/reading-screen {:container-size (:container-size container-info)}))

(defn run-skia!
  [{:keys [width height renders present? batch-text? flash? wait?]}]
  (let [load-native       (requiring-resolve 'ol.membrane.backend.skia/load-native)
        open-context!     (requiring-resolve 'ol.membrane.backend.skia/open-context!)
        close-context!    (requiring-resolve 'ol.membrane.backend.skia/close-context!)
        render-view!      (requiring-resolve 'ol.membrane.backend.skia/render-view!)
        text-cache-stats  (requiring-resolve 'ol.membrane.backend.skia/text-cache-stats)
        opts              {:width                  width
                           :height                 height
                           :present?               (boolean present?)
                           :include-container-info true
                           :skia-batch?            true
                           :skia-batch-text?       (boolean batch-text?)
                           :waveform               :gc16
                           :flash?                 (boolean flash?)
                           :wait?                  (boolean wait?)}
        [native load-ms]  (timed #(load-native))
        [context open-ms] (timed #(open-context! (assoc opts :native native)))]
    (println "MEASUREMENT" (pr-str (measurement-scope opts)))
    (println "SETUP reading skia"
             "batch-text?" (boolean batch-text?)
             "load-native-ms" (format "%.3f" load-ms)
             "open-context-ms" (format "%.3f" open-ms)
             "java2d-loaded?" (contains? (loaded-libs) 'ol.membrane.backend.java2d))
    (flush)
    (try
      (loop [i 1 rows []]
        (if (> i renders)
          rows
          (let [before            (text-cache-stats context)
                [result total-ms] (timed #(render-view! context reading-view opts))
                after             (text-cache-stats context)
                row               {:i                i
                                   :total-ms         total-ms
                                   :timings          (:timings result)
                                   :batch            (:skia-batch result)
                                   :text-cache-delta (delta-stats before after)
                                   :text-cache-total after
                                   :present-kind     (:present-kind result)
                                   :dirty-rect       (:dirty-rect result)}]
            (println "RENDER reading skia" i (format "%.3f" total-ms)
                     "timings" (pr-str (:timings row))
                     "batch" (pr-str (:batch row))
                     "text-cache-delta" (pr-str (:text-cache-delta row))
                     "text-cache-total" (pr-str (:text-cache-total row))
                     "present-kind" (pr-str (:present-kind row))
                     "dirty" (pr-str (:dirty-rect row)))
            (flush)
            (recur (inc i) (conj rows row)))))
      (finally
        (close-context! context)))))

(defn run-java2d!
  [{:keys [width height renders present? flash? wait?]}]
  (let [open-context!     (requiring-resolve 'ol.membrane.backend.java2d/open-context!)
        close-context!    (requiring-resolve 'ol.membrane.backend.java2d/close-context!)
        render-view!      (requiring-resolve 'ol.membrane.backend.java2d/render-view!)
        opts              {:width                  width
                           :height                 height
                           :native?                (boolean present?)
                           :present?               (boolean present?)
                           :include-container-info true
                           :damage?                false
                           :force-full?            true
                           :waveform               :gc16
                           :flash?                 (boolean flash?)
                           :wait?                  (boolean wait?)}
        [context open-ms] (timed #(open-context! opts))]
    (println "MEASUREMENT" (pr-str (measurement-scope opts)))
    (println "SETUP reading java2d"
             "open-context-ms" (format "%.3f" open-ms)
             "java2d-loaded?" (contains? (loaded-libs) 'ol.membrane.backend.java2d))
    (flush)
    (try
      (loop [i 1 rows []]
        (if (> i renders)
          rows
          (let [[result total-ms] (timed #(render-view! context reading-view opts))
                row               {:i            i
                                   :total-ms     total-ms
                                   :timings      (:timings result)
                                   :present-kind (:present-kind result)
                                   :dirty-rect   (:dirty-rect result)}]
            (println "RENDER reading java2d" i (format "%.3f" total-ms)
                     "timings" (pr-str (:timings row))
                     "present-kind" (pr-str (:present-kind row))
                     "dirty" (pr-str (:dirty-rect row)))
            (flush)
            (recur (inc i) (conj rows row)))))
      (finally
        (close-context! context)))))

(defn- parse-int-or
  [value default]
  (try
    (if value (Integer/parseInt (str value)) default)
    (catch Exception _
      default)))

(defn parse-args
  [args]
  (loop [remaining args
         parsed    {:scenario-name "reading-skia"
                    :width         reading/default-width
                    :height        reading/default-height
                    :renders       default-renders
                    :present?      false
                    :flash?        false
                    :wait?         false}]
    (if-let [arg (first remaining)]
      (case arg
        "--width" (recur (nnext remaining) (assoc parsed :width (parse-int-or (second remaining) (:width parsed))))
        "--height" (recur (nnext remaining) (assoc parsed :height (parse-int-or (second remaining) (:height parsed))))
        "--renders" (recur (nnext remaining) (assoc parsed :renders (parse-int-or (second remaining) (:renders parsed))))
        "--present" (recur (next remaining) (assoc parsed :present? true))
        "--no-present" (recur (next remaining) (assoc parsed :present? false))
        "--flash" (recur (next remaining) (assoc parsed :flash? true))
        "--no-flash" (recur (next remaining) (assoc parsed :flash? false))
        "--wait" (recur (next remaining) (assoc parsed :wait? true))
        "--no-wait" (recur (next remaining) (assoc parsed :wait? false))
        (if (str/starts-with? arg "--")
          (throw (ex-info (str "unknown option " arg) {:args args}))
          (recur (next remaining) (assoc parsed :scenario-name arg))))
      parsed)))

(defn -main
  [& args]
  (let [{:keys [scenario-name] :as parsed} (parse-args args)
        scenario                           (get scenarios scenario-name)]
    (when-not scenario
      (throw (ex-info (str "unknown scenario " scenario-name) {:scenarios (keys scenarios)})))
    (let [config (merge scenario parsed)]
      (println "BEGIN" scenario-name (pr-str (dissoc config :scenario-name)))
      (flush)
      (let [rows (case (:backend config)
                   :skia (run-skia! config)
                   :java2d (run-java2d! config))]
        (println "SUMMARY"
                 (pr-str (assoc (summary scenario-name rows)
                                :scenario scenario-name
                                :width (:width config)
                                :height (:height config)
                                :renders (:renders config)
                                :backend (:backend config)
                                :measurement (measurement-scope config)
                                :batch-text? (boolean (:batch-text? config))
                                :last-text-cache-total (:text-cache-total (last rows))
                                :last-text-cache-delta (:text-cache-delta (last rows))
                                :last-batch (:batch (last rows)))))
        (flush)))))
