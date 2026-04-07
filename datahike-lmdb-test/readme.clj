(ns readme)
(require '[datahike.api :as d])
(require '[datahike-lmdb.core])
(defn -main []
  (let [cfg {:store {:backend :lmdb
                     :id #uuid "550e8400-e29b-41d4-a716-446655440000"
                     :path "./data"}
             :schema-flexibility :write
             :keep-history? false}
        _ (when-not (d/database-exists? cfg) (d/create-database cfg))
        conn (d/connect cfg)]
    ;; Use datahike normally
    (d/transact conn [{:db/ident :person/name
                       :db/valueType :db.type/string
                       :db/cardinality :db.cardinality/one}])

    (d/transact conn [{:person/name "Alice"}])

    (prn (d/q '[:find ?n :where [?e :person/name ?n]] @conn))
    ;; => #{["Alice"]}
    (d/release conn)))
