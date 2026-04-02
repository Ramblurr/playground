(ns sqlite4clj-repro
  "Minimal repro for sqlite4clj using the wrong SQLite library at runtime.

   Run from this directory:

     clojure -J--enable-native-access=ALL-UNNAMED -M -m sqlite4clj-repro

   The bundled sqlite4clj build is expected to include markers such as:
   - THREADSAFE=2
   - DEFAULT_WAL_SYNCHRONOUS=1
   - OMIT_SHARED_CACHE
   - ENABLE_STAT4

   If those are missing from `PRAGMA compile_options`, sqlite4clj is not
   executing against its bundled SQLite build."
  (:require [clojure.string :as str]
            [sqlite4clj.core :as d]))

(def expected-bundled-markers
  ["THREADSAFE=2"
   "DEFAULT_WAL_SYNCHRONOUS=1"
   "OMIT_SHARED_CACHE"
   "ENABLE_STAT4"])

(def common-non-bundled-markers
  ["THREADSAFE=1"
   "DEFAULT_WAL_SYNCHRONOUS=2"
   "ENABLE_DBSTAT_VTAB"
   "ENABLE_GEOPOLY"])

(defn interesting-options [opts markers]
  (filter (fn [opt]
            (some #(str/includes? opt %) markers))
          opts))

(defn -main [& _]
  (let [db (d/init-db! "repro.sqlite" {:pool-size 1})
        opts (sort (vec (d/q (:reader db) ["PRAGMA compile_options;"])))
        bundled? (every? (set opts) expected-bundled-markers)]
    (try
      (println (str "\nUsing sqlite4clj's bundled sqlite binaries? " (if bundled? "YES!" "NO :(")))
      (println "\nexpected-bundled-markers:")
      (doseq [opt expected-bundled-markers]
        (println opt))
      (println "observed-related-options:")
      (doseq [opt (interesting-options opts
                                       (concat expected-bundled-markers
                                               common-non-bundled-markers))]
        (println opt))
      (finally
        ((:close (:reader db)))
        ((:close (:writer db)))))))
