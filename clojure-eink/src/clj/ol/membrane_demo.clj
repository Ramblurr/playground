(ns ol.membrane-demo
  (:require
   [membrane.ui :as ui]
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
  [{:keys [container-size]}]
  ((kobo/more-view {:viewport container-size})))

(defn view-for-options
  [{:keys [kobo-more?]}]
  (if kobo-more?
    kobo-more-view
    demo-view))

(defn- loop-request?
  [args]
  (some #{"--loop"} args))

(defn- kobo-more-request?
  [args]
  (some #{"--kobo-more" "--more"} args))

(defn- without-demo-runner-flags
  [args]
  (remove #{"--loop" "--kobo-more" "--more"} args))

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
  (let [loop?      (loop-request? args)
        kobo-more? (kobo-more-request? args)
        opts       (assoc (project/parse-args (without-demo-runner-flags args))
                          :kobo-more? kobo-more?)
        view-fn    (view-for-options opts)]
    (project/log-time! "parsed args")
    (if (:help? opts)
      (do
        (println (project/usage))
        (println "Membrane demo options: --loop --kobo-more/--more"))
      (if loop?
        (backend/run-loop! view-fn (assoc opts
                                          :include-container-info true
                                          :reload! reload-demo!))
        (run-once! view-fn opts)))))
