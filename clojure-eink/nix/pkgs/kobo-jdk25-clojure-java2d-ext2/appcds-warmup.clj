(require '[clojure.string :as str]
         '[clojure.set :as set]
         '[clojure.walk :as walk]
         '[clojure.java.io :as io]
         '[clojure.edn :as edn]
         '[clojure.repl :as repl]
         '[clojure.pprint :as pprint]
         '[clojure.stacktrace :as stacktrace]
         '[clojure.template :as template]
         '[clojure.core.server :as server]
         '[clojure.test :as test])
(str/join "," ["a" "b" "c"])
(set/union #{1 2} #{2 3})
(walk/postwalk identity {:a [1 2 {:b 3}]})
(edn/read-string "{:a [1 2 3]}")
(with-out-str (pprint/pprint {:k [1 2 3]}))
(with-out-str (repl/doc +))
(println (+ 40 2))
