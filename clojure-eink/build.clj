;; Copyright © 2025 Casey Link <casey@outskirtslabs.com>
;; SPDX-License-Identifier: MIT
(ns build
  (:require [clojure.tools.build.api :as b]
            [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]))

(def project (-> (edn/read-string (slurp "deps.edn")) :aliases :neil :project))
(def lib (:name project))
(def version (:version project))
(def license-id (-> project :license :id))
(def license-file (or (-> project :license :file) "LICENSE"))
(def description (:description project))

(defn- git-origin-url []
  (try
    (some-> (b/git-process {:git-args "remote get-url origin"})
            str/trim
            (str/replace #"\.git$" ""))
    (catch Exception _
      nil)))

(defn- git-rev []
  (or (some-> (System/getenv "GIT_REV")
              str/trim
              not-empty)
      (some-> (b/git-process {:git-args "rev-parse HEAD"})
              str/trim
              not-empty)))

(def rev (git-rev))
(def repo-url-prefix (or (:url project) (git-origin-url)))
(assert lib ":name must be set in deps.edn under the :neil alias")
(assert version ":version must be set in deps.edn under the :neil alias")
(assert description ":description must be set in deps.edn under the :neil alias")
(assert license-id "[:license :id] must be set in deps.edn under the :neil alias")
(assert rev "Either GIT_REV must be set or git rev-parse HEAD must succeed")
(assert repo-url-prefix "Either :url must be set in deps.edn under the :neil alias or git remote origin must exist")
(def class-dir "target/classes")
(def aot-class-dir "target/aot/classes")
(def aot-jar-file "target/clojure-eink-demo-aot.jar")
(def aot-clojure-version "1.12.4")
(def aot-namespaces
  '[ol.membrane-demo
    ol.membrane-skia-demo])
(def basis_ (delay (b/create-basis {:project "deps.edn"})))
(def jar-file (format "target/%s-%s.jar" (name lib) version))

(defn- existing-paths [paths]
  (->> paths
       (filter #(.exists (io/file %)))
       vec))

(defn permalink [subpath]
  (str repo-url-prefix "/blob/" rev "/" subpath))

(defn url->scm [url-string]
  (let [[_ domain repo-path] (re-find #"https?://?([\w\-\.]+)/(.+)" url-string)]
    [:scm
     [:url (str "https://" domain "/" repo-path)]
     [:connection (str "scm:git:https://" domain "/" repo-path)]
     [:developerConnection (str "scm:git:ssh:git@" domain ":" repo-path)]]))

(defn- run-process!
  [command-args]
  (let [{:keys [exit] :as result} (b/process {:command-args command-args})]
    (when-not (zero? exit)
      (throw (ex-info (str "command failed: " (str/join " " command-args))
                      (assoc result :command-args command-args)))))
  nil)

(defn- aot-compile-form []
  (pr-str
   `(do
      (binding [*compile-path* ~aot-class-dir]
        ~@(map (fn [namespace]
                 `(compile '~namespace))
               aot-namespaces)))))

(defn clean [_]
  (b/delete {:path "target"}))

(defn jar [_]
  (b/write-pom {:class-dir class-dir
                :lib       lib
                :version   version
                :basis     @basis_
                :src-dirs  (existing-paths ["src/clj" "resources"])
                :pom-data  [[:description description]
                            [:url repo-url-prefix]
                            [:licenses
                             [:license
                              [:name license-id]
                              [:url (permalink license-file)]]]
                            (conj (url->scm repo-url-prefix) [:tag rev])]})

  (b/copy-dir {:src-dirs   (existing-paths ["src/clj" "resources"])
               :target-dir class-dir})
  (b/jar {:class-dir class-dir
          :jar-file  jar-file}))

(defn aot-jar [_]
  (b/delete {:path "target/aot"})
  (.mkdirs (io/file aot-class-dir))
  (run-process!
   ["clojure"
    "-Sdeps"
    (format "{:deps {org.clojure/clojure {:mvn/version \"%s\"}}}" aot-clojure-version)
    "-M"
    "-e"
    (aot-compile-form)])
  (run-process! ["sh" "-c" (format "jar c0f %s -C %s ." aot-jar-file aot-class-dir)])
  {:aot-jar-file aot-jar-file
   :class-dir    aot-class-dir
   :namespaces   aot-namespaces})

(defn install [_]
  (jar {})
  (b/install {:basis     @basis_
              :lib       lib
              :version   version
              :jar-file  jar-file
              :class-dir class-dir}))

(defn deploy [opts]
  (jar opts)
  ((requiring-resolve 'deps-deploy.deps-deploy/deploy)
   (merge {:installer :remote
           :artifact  jar-file
           :pom-file  (b/pom-path {:lib lib :class-dir class-dir})}
          opts))
  opts)
