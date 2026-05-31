(ns ol.membrane-demo
  (:require
   [clojure.string :as str]
   [membrane.component :as component]
   [membrane.ui :as ui]
   [ol.input.kobo :as input.kobo]
   [ol.membrane-demo.kobo :as kobo]
   [ol.membrane.eink-backend :as backend]
   [ol.project :as project]))

(defn- centered-label
  [text font width height]
  (let [[label-width label-height] (backend/text-bounds font text)]
    (ui/translate (/ (- width label-width) 2.0)
                  (/ (- height label-height) 2.0)
                  (ui/label text font))))

(defn demo-ui
  [{:keys [width height]
    :or   {width 800 height 600}}]
  (let [title-font    (ui/font nil 42)
        body-font     (ui/font nil 30)
        button-font   (ui/font nil 28)
        button-width  360
        button-height 82
        button-radius 8
        content       [(ui/with-color [1 1 1]
                         (ui/rectangle width height))
                       (ui/with-color [0 0 0]
                         (ui/translate 48 72
                                       (ui/label "Membrane on FBInk" title-font))
                         (ui/translate 48 136
                                       (ui/label "Java2D grayscale -> FBInk" body-font)))
                       (ui/translate 48 210
                                     [(ui/with-color [0.94 0.94 0.94]
                                        (ui/rounded-rectangle button-width button-height button-radius))
                                      (ui/with-color [0 0 0]
                                        (ui/with-stroke-width
                                          3
                                          (ui/with-style :membrane.ui/style-stroke
                                            (ui/rounded-rectangle button-width button-height button-radius)))
                                        (centered-label "Click Me" button-font button-width button-height))])]]
    (ui/fixed-bounds [width height] content)))
(defn- demo-view
  [{:keys [container-size]}]
  (let [[width height] container-size]
    (demo-ui {:width width :height height})))

(defn- kobo-more-view
  []
  (let [state (atom kobo/default-more-state)
        app   (component/make-app #'kobo/more-screen state)]
    (fn
      ([]
       (app))
      ([{:keys [container-size] :as container-info}]
       (when container-size
         (swap! state assoc :viewport container-size))
       (app container-info)))))

(defn view-for-options
  [{:keys [kobo-more?]}]
  (if kobo-more?
    (kobo-more-view)
    demo-view))

(defn- option-value
  [option value]
  (when-not value
    (throw (ex-info (str "missing value for " option) {:option option})))
  value)

(defn- parse-input-profile-option
  [option value]
  (-> (option-value option value)
      str/lower-case
      keyword
      input.kobo/profile
      :name))

(defn parse-runner-args
  [args]
  (loop [runner-opts  {:loop?               false
                       :kobo-more?          false
                       :input?              false
                       :input-dump?         false
                       :input-raw-dump?     false
                       :input-grab?         false
                       :input-render-moves? false
                       :verbose-input?      false}
         project-args []
         xs           (seq args)]
    (if-not xs
      {:runner-opts  runner-opts
       :project-args project-args}
      (let [[arg & more] xs]
        (case arg
          "--loop"
          (recur (assoc runner-opts :loop? true) project-args more)

          ("--kobo-more" "--more")
          (recur (assoc runner-opts :kobo-more? true) project-args more)

          "--input"
          (recur (assoc runner-opts :input? true) project-args more)

          "--input-dump"
          (recur (assoc runner-opts :input? true :input-dump? true :verbose-input? true) project-args more)

          "--input-raw-dump"
          (recur (assoc runner-opts :input? true :input-raw-dump? true) project-args more)

          "--input-grab"
          (recur (assoc runner-opts :input-grab? true) project-args more)

          "--no-input-grab"
          (recur (assoc runner-opts :input-grab? false) project-args more)

          "--input-profile"
          (recur (assoc runner-opts :input-profile (parse-input-profile-option arg (first more)))
                 project-args
                 (next more))

          "--input-render-moves"
          (recur (assoc runner-opts :input-render-moves? true) project-args more)

          "--verbose-input"
          (recur (assoc runner-opts :verbose-input? true) project-args more)

          (recur runner-opts (conj project-args arg) more))))))

(defn options-for-args
  [args]
  (let [{:keys [runner-opts project-args]} (parse-runner-args args)
        explicit-no-present?               (boolean (some #{"--no-present"} project-args))
        opts                               (merge (project/parse-args project-args) runner-opts)]
    (cond-> opts
      (:input? opts) (assoc :native? true)
      (and (:input? opts) (not explicit-no-present?)) (assoc :present? true :present-mode :each))))

(defn- reload-demo!
  []
  (doseq [path ["src/clj/ol/membrane/eink_backend.clj"
                "src/clj/ol/membrane_demo.clj"
                "src/clj/ol/membrane_demo/kobo.clj"]]
    (load-file path)
    (println "reloaded" path))
  (flush))

(defn- run-once!
  [view-fn opts]
  (let [context (backend/open-context! opts)]
    (try
      (let [width  (:width context)
            height (:height context)
            result (do
                     (project/log-time! (str "starting Membrane render " width "x" height))
                     (let [result (backend/render-view! context
                                                        view-fn
                                                        (assoc opts :include-container-info true))]
                       (project/log-time! "finished Membrane render")
                       result))
            image  (:image result)]
        (when-let [png (:png opts)]
          (project/log-time! "starting PNG write")
          (println "wrote" (project/write-png! image png))
          (project/log-time! "finished PNG write"))
        (if (:presented? result)
          (println "presented Membrane demo" width "x" height "via" (:native-lib context)
                   "mode" (name (:present-kind result)))
          (println "rendered Membrane demo" width "x" height "without native present"
                   "mode" (name (or (:present-kind result) :no-present))))
        result)
      (finally
        (backend/close-context! context)))))

(defn -main
  [& args]
  (project/log-time! "entered ol.membrane-demo/-main")
  (let [opts    (options-for-args args)
        view-fn (view-for-options opts)]
    (project/log-time! "parsed args")
    (if (:help? opts)
      (do
        (println (project/usage))
        (println "Membrane demo options: --loop --kobo-more/--more --input --input-dump --input-raw-dump --input-grab --no-input-grab --input-profile none|switch-xy|kobo-default|kobo-mirror-y --input-render-moves --verbose-input"))
      (cond
        (:input? opts)
        (backend/run-input-loop! view-fn opts)

        (:loop? opts)
        (backend/run-loop! view-fn (assoc opts
                                          :include-container-info true
                                          :reload! reload-demo!))

        :else
        (run-once! view-fn opts)))))