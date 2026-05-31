(ns ol.loop
  (:require
   [clojure.java.io :as io]
   [clojure.string :as str]
   [ol.project :as project]))

(defn parse-command-line
  [line]
  (let [tokens (-> line str/trim (str/split #"\s+"))]
    (if (or (empty? tokens)
            (= [""] tokens))
      {:command :blank :args []}
      {:command (keyword (str/lower-case (first tokens)))
       :args    (vec (rest tokens))})))

(defn- reload-file-path
  []
  (or (System/getenv "EINK_RELOAD_FILE")
      (System/getProperty "eink.reload.file")
      "src/clj/ol/project.clj"))

(defn- resolve-project-fn
  [sym]
  (deref (requiring-resolve sym)))

(defn reload-project!
  ([]
   (reload-project! (reload-file-path)))
  ([path]
   (let [file (io/file path)]
     (when-not (.exists file)
       (throw (ex-info (str "reload file does not exist: " path) {:path path})))
     (load-file (.getPath file))
     (println "reloaded" (.getPath file))
     (flush))))

(defn- print-help!
  []
  (println "Commands:")
  (println "  render [demo options]   render without restarting the JVM")
  (println "  reload                  load src/clj/ol/project.clj, or EINK_RELOAD_FILE")
  (println "  help                    print this help")
  (println "  quit                    close native backend and exit")
  (flush))

(defn- prompt!
  []
  (print "eink> ")
  (flush))

(defn- load-native-context!
  [base-opts]
  (let [native-lib (or (:native-lib base-opts) (project/default-native-lib))
        native     (when (:native? base-opts)
                     (when-not native-lib
                       (throw (ex-info "native library path not provided and no default native library was found" {})))
                     (let [loaded (project/load-native native-lib)]
                       (project/log-time! "loaded native library and linked symbols")
                       loaded))]
    (when native
      (project/init-native! native)
      (project/log-time! "initialized FBInk/native backend"))
    (let [width  (or (:width base-opts)
                     (when native
                       (let [w (project/native-screen-width native)]
                         (project/log-time! (str "queried screen width: " w))
                         w))
                     800)
          height (or (:height base-opts)
                     (when native
                       (let [h (project/native-screen-height native)]
                         (project/log-time! (str "queried screen height: " h))
                         h))
                     600)]
      {:native     native
       :native-lib native-lib
       :width      width
       :height     height})))

(defn- render-command!
  [base-opts context args]
  (let [parse-args! (resolve-project-fn 'ol.project/parse-args)
        benchmark!  (resolve-project-fn 'ol.project/benchmark-renders!)
        opts        (assoc (parse-args! base-opts args)
                           :native (:native context)
                           :native-lib (:native-lib context)
                           :width (:width context)
                           :height (:height context))]
    (benchmark! opts)))

(defn run-loop!
  [base-opts]
  (let [context (load-native-context! base-opts)]
    (println "ready: long-lived clojure-eink loop")
    (print-help!)
    (try
      (loop []
        (prompt!)
        (if-let [line (read-line)]
          (let [{:keys [command args]} (parse-command-line line)]
            (case command
              :blank (recur)
              :help (do (print-help!) (recur))
              :reload (do (reload-project!) (recur))
              :render (do (render-command! base-opts context args) (recur))
              :quit :quit
              :exit :quit
              (do
                (println "unknown command:" (name command))
                (print-help!)
                (recur))))
          :eof))
      (finally
        (when-let [native (:native context)]
          (project/log-time! "closing native backend")
          (project/close-native! native)
          (project/log-time! "closed native backend"))))))

(defn -main
  [& args]
  (project/log-time! "entered ol.loop/-main")
  (let [base-opts (project/parse-args args)]
    (project/log-time! "parsed loop args")
    (if (:help? base-opts)
      (do
        (println (project/usage))
        (print-help!))
      (run-loop! base-opts))))
