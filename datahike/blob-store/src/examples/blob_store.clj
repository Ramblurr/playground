(ns examples.blob-store
  (:gen-class)
  (:require [clojure.java.io :as io]
            [datahike.api :as d]
            [konserve.core :as k]
            [taoensso.trove :as trove]
            [taoensso.trove.console :as trove.console]))
(trove/set-log-fn! (trove.console/get-log-fn {:min-level :warn}))

(def schema
  [{:db/ident :document/id
    :db/valueType :db.type/uuid
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :document/title
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :document/blob-key
    :db/valueType :db.type/uuid
    :db/cardinality :db.cardinality/one}
   {:db/ident :document/char-count
    :db/valueType :db.type/long
    :db/cardinality :db.cardinality/one}])

(defn setup []
  (let [temp-dir (.toFile (java.nio.file.Files/createTempDirectory
                           "datahike-blob-store-"
                           (make-array java.nio.file.attribute.FileAttribute 0)))
        _ (.addShutdownHook
           (Runtime/getRuntime)
           (Thread.
            (fn []
              (when (.exists ^java.io.File temp-dir)
                (doseq [^java.io.File child (reverse (file-seq temp-dir))]
                  (.delete child))))))
        db-dir (io/file temp-dir "datahike")
        blob-dir (io/file temp-dir "blob-store")
        db-cfg {:store {:backend :file
                        :path (.getPath ^java.io.File db-dir)
                        :id (random-uuid)}}
        blob-store-cfg {:backend :file
                        :path (.getPath ^java.io.File blob-dir)
                        :id (random-uuid)}]
    [db-cfg blob-store-cfg]))

(defn -main [& _args]
  (let [[db-cfg blob-store-cfg] (setup)
        _ (d/create-database db-cfg)
        conn (d/connect db-cfg)
        blob-store (k/create-store blob-store-cfg {:sync? true})]
    (try
      (d/transact conn schema)
      (let [document-id (random-uuid)
            blob-key (random-uuid)
            large-string (apply str (repeat 12288 \A))
            char-count (long (count large-string))]
        (k/assoc blob-store blob-key large-string {:sync? true})
        (d/transact conn [{:document/id document-id
                           :document/title "Large string stored outside Datahike"
                           :document/blob-key blob-key
                           :document/char-count char-count}])
        (let [query-result
              (d/q '[:find ?title ?char-count ?body
                     :in $ ?blob-store
                     :where
                     [?e :document/title ?title]
                     [?e :document/char-count ?char-count]
                     [?e :document/blob-key ?blob-key]
                     [(konserve.core/get ?blob-store ?blob-key nil {:sync? true}) ?body]]
                   @conn
                   blob-store)]
          (assert (= #{["Large string stored outside Datahike"
                        char-count
                        large-string]}
                     query-result))
          (prn
           (update (first query-result) 2 #(str (subs % 0 20) "...")))))
      (finally
        (d/release conn)
        (k/release-store blob-store-cfg blob-store {:sync? true})))))
